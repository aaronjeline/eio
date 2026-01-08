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

(* The type of items in the run queue. *)
type runnable =
  | IO : runnable                                       (* Reminder to check for IO *)
  | Thread : 'a Suspended.t * 'a -> runnable            (* Resume a fiber with a result value *)
  | Failed_thread : 'a Suspended.t * exn -> runnable    (* Resume a fiber with an exception *)

(* For each FD we track which fibers are waiting for it to become readable/writeable. *)
type fd_event_waiters = {
  read : unit Suspended.t Lwt_dllist.t;
  write : unit Suspended.t Lwt_dllist.t;
}