(*
 * Copyright (C) 2025 Aaron Eline
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *)
module Suspended = Eio_utils.Suspended
module Lf_queue = Eio_utils.Lf_queue
module Rcfd = Eio_unix.Private.Rcfd
module Eventfd = Posix_eventfd
open Sched_common

type internal_state = {
  (* The (write handle) queue of runnable computations maintained by the main schedular thread  *)
  main_q : runnable Lf_queue.t;
  (* The (read handle) of incoming files we need to track  *)
  incoming_files : (Unix.file_descr * fd_event_waiters) Lf_queue.t ;
  (* Map from file descriptors to tasks waiting on data from that descriptor  *)
  map : (Unix.file_descr, fd_event_waiters) Hashtbl.t;
  (* Set of file descriptors we pass to select() to read from  *)
  read_set : Unix.file_descr list ref;
  (* Set of file descriptors we pass to select() to write to *)
  write_set : Unix.file_descr list ref;
  (* atomic global count of in-flight IO requets  *)
  active_ops : int Atomic.t;
  (* event fds *)
  eventfd : Eventfd.Owner.t;
  main_eventfd : Eventfd.Writer.t;
  (* atomic bool that tracks if we should shutdown  *)
  shutdown : bool Atomic.t;
}

(* The public (opaque) handle to a select thread *)
type t = {
  state : internal_state;
  thread : Thread.t;
}

let queue t = t.state.incoming_files

let eventfd t = Eventfd.Owner.create_writer t.state.eventfd

let add_fd fd waiters t  =
  Lf_queue.push (queue t) (fd, waiters);
  Eventfd.Writer.wakeup (eventfd t)

(** Read from our incoming queue and track requests,
  mutates the fd sets and the fd -> waiters mapping
*)
let queue_events t =
  let more_events = ref true in
  while !more_events do
    match Lf_queue.pop t.incoming_files with
    | None -> more_events := false
    | Some (fd, waiters) ->
      if not (Lwt_dllist.is_empty waiters.write) then
        t.write_set := fd :: !(t.write_set);
      if not (Lwt_dllist.is_empty waiters.read) then
        t.read_set := fd :: !(t.read_set);
      Hashtbl.add t.map fd waiters
  done

(**
  Process the returned fds from select() and update either the read or write fdsets
  @param returned_fds The fdset returned by select()
  @param sent_fds The input fdset we're going to modify 
  @param access function for access the relevant part of fd_event_waiters (either read or write)
  @param state the internal state for the select thread
  @return bool indicating if we resumed any computations
*)
let process_fd_set returned_fds sent_fds access state = 
  (* tracks the fds that we removed from the input sets *)
  let removed = Dynarray.create () in
  (* tracks the suspended computations we need to queue *)
  let to_queue = Lwt_dllist.create () in
  List.iter (
    fun fd -> 
      if not (Eventfd.Owner.is_reader fd state.eventfd) then begin
        let waiters = Hashtbl.find state.map fd in
        let lst = access waiters in 
        Lwt_dllist.transfer_l lst to_queue;
        Dynarray.add_last removed fd;
      end
  ) returned_fds;
  (* retain all fds that we did not process *)
  sent_fds := List.filter (fun fd -> not (Dynarray.mem fd removed)) !sent_fds;
  (* for each computation we need to resume, 
      1) Decrease our count of in-flight ops
      2) Push the computation to the schedulars list of active threads *)
  Lwt_dllist.iter_l (fun k ->
    Atomic.decr state.active_ops;
    Lf_queue.push state.main_q (Thread (k, ()))
  ) to_queue;
  not (Dynarray.is_empty removed)

(* Main loop for the select thread *)
let rec select_loop t =
  if Atomic.get t.shutdown then
    Eventfd.Owner.cleanup t.eventfd
  else begin
    (* Block on select, we will be woken up by one of two things
     1) the eventfd being written to, which signals we need to from our queue
     2) one of the fds were tracking being read/written to, which means we need to resume a computation *)
    let read_fd = Eventfd.Owner.reader_fd t.eventfd in
    let read_set = read_fd :: !(t.read_set) in
    let (r, w, _) = Unix.select read_set !(t.write_set) [] (-1.0) in
    if List.mem read_fd r then begin
      Eventfd.Owner.clear t.eventfd; (* clear events *)
      queue_events t
    end;
    let at_least_one_reader = process_fd_set r t.read_set (fun waiters -> waiters.read) t in
    let at_least_one_writer = process_fd_set w t.write_set (fun waiters -> waiters.write) t in
    if at_least_one_reader || at_least_one_writer then
      Eventfd.Writer.wakeup t.main_eventfd;
    select_loop t
  end

let cleanup t =
  Atomic.set t.state.shutdown true;
  Eventfd.Writer.wakeup (Eventfd.Owner.create_writer t.state.eventfd);
  Thread.join t.thread

let init main_q main_eventfd active_ops =
  let eventfd = Eventfd.Owner.create () in
  let state = {
    main_q;
    incoming_files = Lf_queue.create ();
    main_eventfd;
    active_ops;
    map = Hashtbl.create 10;
    read_set = ref [];
    write_set = ref [];
    eventfd;
    shutdown = Atomic.make false;
  } in
  let thread = Thread.create (fun () -> select_loop state) () in
  { state; thread }
