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
module Rcfd = Eio_unix.Private.Rcfd

module Writer = struct
  type t = Rcfd.t
  let wake_buffer = Bytes.of_string "!"
  let wakeup t = 
    Rcfd.use t
      ~if_closed:ignore
      (fun fd -> 
        try 
          ignore (Unix.single_write fd wake_buffer 0 1)
        with
         (* If the pipe is full then a wake up is pending anyway. *)
          | Unix.Unix_error ((Unix.EACCES | EWOULDBLOCK), _, _) -> ()
         (* We're shutting down; the event has already been processed. *)
          | Unix.Unix_error (Unix.EPIPE, _, _) -> ()
      )
end 

module Owner = struct 
  type t = {
    read : Unix.file_descr;
    write : Rcfd.t;
  }

  let is_reader fd t = fd = t.read

  let reader_fd t = t.read

  let create_writer t = t.write

  let clear t = 
    let buf = Bytes.create 8 in
    let got = Unix.read t.read buf 0 (Bytes.length buf) in
    assert (got > 0)

  let create () = 
    let read, write = Unix.pipe ~cloexec:true () in
    Unix.set_nonblock read;
    Unix.set_nonblock write;
    let write = Rcfd.make write in
    {
      read; write
    }

  let cleanup t = 
    Unix.close t.read;
    let was_open = Rcfd.close t.write in
    assert was_open

end