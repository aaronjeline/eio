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

(**
    This module implements a thread safe re-usable abstraction for POSIX compliant eventfds.
    Eventfds are backed by a pipe.
*)

(**
 The [Writer] module is the writing end of the eventfd. 
 Having a [Writer.t] allows you to signal to the holder of the owner to wake up
 It is safe to share between threads
*)
module Writer :
  sig type t

  (** Signal to the owning thread to wake up *)
  val wakeup : t -> unit
end

(**
    The [Owner] module is the reading end of the event fd.
    It is not safe to share between threads.
    Anyone who holds a [Writer.t] can send wake up signals to an [Owner.t]
*)
module Owner :
  sig
    type t

    (** Check if a given fd is the read end of the event fd *)
    val is_reader : Unix.file_descr -> t -> bool

    (** @return the reading fd of the eventfd. This is not safe to share between threads. *)
    val reader_fd : t -> Unix.file_descr

    (** Get a view into the write end of the event fd.
        @return the writing end. Safe to share between threads. *)
    val create_writer : t -> Writer.t

    (** Clear pending events from the event fd *)
    val clear : t -> unit

    (** @return a new eventfd owner *)
    val create : unit -> t

    (** Close the file descriptors associated with the eventfd *)
    val cleanup : t -> unit
  end
