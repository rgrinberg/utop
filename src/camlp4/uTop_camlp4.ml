(*
 * uTop_camlp4.ml
 * --------------
 * Copyright : (c) 2012, Jeremie Dimino <jeremie@dimino.org>
 * Licence   : BSD3
 *
 * This file is a part of utop.
 *)

open Lexing
open Camlp4
open Camlp4.PreCast

module Ast2pt = Camlp4.Struct.Camlp4Ast2OCamlAst.Make(Ast)

external cast_toplevel_phrase : Camlp4_import.Parsetree.toplevel_phrase -> Parsetree.toplevel_phrase = "%identity"

let print_camlp4_error pp exn =
  Format.fprintf pp "@[<0>%a@]" Camlp4.ErrorHandler.print exn;
  Format.pp_print_flush pp ()

let get_camlp4_error_message exn =
  let loc, exn =
    match exn with
      | Loc.Exc_located (loc, exn) ->
          ((Loc.start_off loc, Loc.stop_off loc), exn)
      | exn ->
          ((0, 0), exn)
  in
  let msg = UTop.get_message print_camlp4_error exn in
  (* Camlp4 sometimes generate several empty lines at the end... *)
  let idx = ref (String.length msg - 1) in
  while !idx > 0 && msg.[!idx] = '\n' do
    decr idx
  done;
  if !idx + 1 < String.length msg then
    (loc, String.sub msg 0 (!idx + 1))
  else
    (loc, msg)

let convert_camlp4_toplevel_phrase ast =
  try
    UTop.Value (cast_toplevel_phrase (Ast2pt.phrase ast))
  with exn ->
    let loc, msg = get_camlp4_error_message exn in
    UTop.Error ([loc], msg)

let parse_toplevel_phrase_camlp4 str eos_is_error =
  (* Execute delayed actions now. *)
  Register.iter_and_take_callbacks (fun (_, f) -> f ());
  let eof = ref false in
  try
    let token_stream = Gram.filter (Gram.lex_string (Loc.mk UTop.input_name) str) in
    let token_stream =
      Stream.from
        (fun _ ->
           match Stream.next token_stream with
             | (EOI, _) as x ->
                 eof := true;
                 Some x
             | x ->
                 Some x)
    in
    match Gram.parse_tokens_after_filter Syntax.top_phrase token_stream with
      | Some ast ->
          let ast = AstFilters.fold_topphrase_filters (fun t filter -> filter t) ast in
          UTop.Value ast
      | None ->
          raise UTop.Need_more
  with exn ->
    if !eof && not eos_is_error then
      raise UTop.Need_more
    else
      let loc, msg = get_camlp4_error_message exn in
      UTop.Error ([loc], msg)

let parse_toplevel_phrase str eos_is_error =
  match parse_toplevel_phrase_camlp4 str eos_is_error with
    | UTop.Value ast ->
        convert_camlp4_toplevel_phrase ast
    | UTop.Error (locs, msg) ->
        UTop.Error (locs, msg)

let () =
  UTop.parse_toplevel_phrase := parse_toplevel_phrase;
  (* Force camlp4 to display its welcome message. *)
  try
    ignore (!Toploop.parse_toplevel_phrase (Lexing.from_string ""))
  with _ ->
    ()
