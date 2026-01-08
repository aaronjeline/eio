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
module Suspended = Sched_common.Suspended
module Lf_queue = Sched_common.Lf_queue
module Rcfd = Sched_common.Rcfd
module Eventfd = Posix_eventfd

(** Handle to the select thread for cleanup *)
type t

(** Initialize the select thread *)
val init :
  Sched_common.runnable Sched_common.Lf_queue.t ->
  Eventfd.Writer.t -> int Atomic.t -> t

(** Request that a file descriptor be tracked by the select thread *)
val add_fd : Unix.file_descr -> Sched_common.fd_event_waiters -> t -> unit

(** Clean up the select thread (signals shutdown and joins the thread) *)
val cleanup : t -> unit