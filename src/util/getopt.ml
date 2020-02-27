(********************************************************************)
(*                                                                  *)
(*  The Why3 Verification Platform   /   The Why3 Development Team  *)
(*  Copyright 2010-2019   --   Inria - CNRS - Paris-Sud University  *)
(*                                                                  *)
(*  This software is distributed under the terms of the GNU Lesser  *)
(*  General Public License version 2.1, with the special exception  *)
(*  on linking described in file LICENSE.                           *)
(*                                                                  *)
(********************************************************************)

type key =
  | KShort of char
  | KLong of string
  | Key of char * string

type _ arg =
  | AInt : int arg
  | AString : string arg
  | ASymbol : string list -> string arg
  | APair : char * 'a arg * 'b arg -> ('a * 'b) arg

type handler =
  | Hnd0 of (unit -> unit)
  | HndOpt : 'a arg * ('a option -> unit) -> handler
  | Hnd1 : 'a arg * ('a -> unit) -> handler

type doc = string

type opt = key * handler * doc

let sprintf = Printf.sprintf

let format margin acc opt =
  let arg, doc =
    let (_, _, doc) = opt in
    match String.index doc ' ' with
    | idx -> String.sub doc 0 idx, String.sub doc (idx + 1) (String.length doc - idx - 1)
    | exception Not_found -> "", doc in
  let key =
    match opt with
    | (KShort c, Hnd0 _,     _) -> sprintf "  -%c" c
    | (KShort c, HndOpt _,   _) -> sprintf "  -%c[%s]" c arg
    | (KShort c, Hnd1 _,     _) -> sprintf "  -%c %s" c arg
    | (KLong s, Hnd0 _,      _) -> sprintf "      --%s" s
    | (KLong s, HndOpt _,    _) -> sprintf "      --%s[=%s]" s arg
    | (KLong s, Hnd1 _,      _) -> sprintf "      --%s=%s" s arg
    | (Key (c, s), Hnd0 _,   _) -> sprintf "  -%c, --%s" c s
    | (Key (c, s), HndOpt _, _) -> sprintf "  -%c, --%s[=%s]" c s arg
    | (Key (c, s), Hnd1 _,   _) -> sprintf "  -%c, --%s=%s" c s arg in
  Buffer.add_string acc key;
  let doc = Strings.split '\n' doc in
  match doc with
  | [] -> ()
  | l :: ls ->
      let n = margin - String.length key in
      let n = if n < 2 then 2 else n in
      for _i = 1 to n do Buffer.add_char acc ' ' done;
      Buffer.add_string acc l;
      Buffer.add_char acc '\n';
      let pad = String.make margin ' ' in
      List.iter (fun l -> Printf.bprintf acc "%s%s\n" pad l) ls

let format ?(margin=25) opts =
  let acc = Buffer.create 1024 in
  List.iter (format margin acc) opts;
  Buffer.contents acc

exception GetoptFailure of string

let rec find_short opts key =
  match opts with
  | [] -> raise (GetoptFailure (sprintf "unrecognized option '-%c'" key))
  | (KShort c, h, _) :: _ when c = key -> h
  | (Key (c, _), h, _) :: _ when c = key -> h
  | _ :: l -> find_short l key

let rec find_long opts key =
  match opts with
  | [] -> raise (GetoptFailure (sprintf "unrecognized option '--%s'" key))
  | (KLong s, h, _) :: _ when s = key -> h
  | (Key (_, s), h, _) :: _ when s = key -> h
  | _ :: l -> find_long l key

let rec parse_kind : type a. string -> a arg -> (a -> unit) -> string -> int -> unit =
  fun key k f arg i ->
  let s = String.sub arg i (String.length arg - i) in
  let fail () = raise (GetoptFailure (sprintf "invalid %s argument '%s'" key s)) in
  match k with
  | AString -> f s
  | ASymbol l ->
      if List.mem s l then f s
      else fail ()
  | APair (c, k1, k2) ->
      begin match String.index_from arg i c with
      | j ->
          parse_kind key k1
            (fun a1 -> parse_kind key k2 (fun a2 -> f (a1, a2)) arg (j + 1))
            (String.sub arg i (j - i)) 0
      | exception Not_found -> fail ()
      end
  | AInt ->
    match int_of_string s with
    | i -> f i
    | exception Failure _ -> fail ()

let parse_short opts arg =
  let len = String.length arg in
  assert (len >= 2);
  match find_short opts arg.[1] with
  | Hnd0 f ->
      f ();
      for j = 2 to len - 1 do
        let key = arg.[j] in
        match find_short opts arg.[j] with
        | Hnd0 f -> f ()
        | HndOpt (_, f) -> f None
        | Hnd1 _ ->
            raise (GetoptFailure (sprintf "option -%c requires an argument" key))
      done;
      None
  | HndOpt (k, f) ->
      if len = 2 then f None
      else parse_kind (String.sub arg 0 2) k (fun x -> f (Some x)) arg 2;
      None
  | Hnd1 (k, f) ->
      if len = 2 then
        Some (fun x -> parse_kind arg k f x 0)
      else
        let () = parse_kind (String.sub arg 0 2) k f arg 2 in
        None

let parse_long opts arg =
  let pos, value =
    match String.index arg '=' with
    | i -> i, Some (i + 1)
    | exception Not_found -> String.length arg, None in
  let key = String.sub arg 2 (pos - 2) in
  match find_long opts key, value with
  | Hnd0 f, None -> f ()
  | HndOpt (_, f), None -> f None
  | HndOpt (k, f), Some i ->
      parse_kind (String.sub arg 0 pos) k (fun x -> f (Some x)) arg i
  | Hnd1 (k, f), Some i ->
      parse_kind (String.sub arg 0 pos) k f arg i
  | Hnd0 _, Some _
  | Hnd1 _, None ->
      raise (GetoptFailure (sprintf "option --%s requires an argument" key))

let parse_one opts args i =
  let nargs = Array.length args in
  assert (0 <= i && i < nargs);
  let arg = args.(i) in
  let len = String.length arg in
  if len < 2 || arg.[0] <> '-' then
    i
  else if arg.[1] = '-' then
    if len = 2 then i (* exit on '--' *)
    else
      let () = parse_long opts arg in
      i + 1
  else
    let i = i + 1 in
    match parse_short opts arg with
    | Some f ->
        if i = nargs then
          raise (GetoptFailure (sprintf "option -%c requires an argument" arg.[1]));
        f (args.(i));
        i + 1
    | None -> i

let handle_exn args exn =
  match exn with
  | GetoptFailure err ->
      if Array.length args <> 0 then
        let p = Filename.basename args.(0) in
        Printf.eprintf "%s: %s\nTry '%s --help' for more information.\n%!" p err p
      else
        Printf.eprintf "%s\nTry '--help' for more information.\n%!" err;
      exit 1
  | _ -> assert false

let parse_many opts args i =
  let nargs = Array.length args in
  let rec aux i =
    if i = nargs then i
    else
      let j = parse_one opts args i in
      if j <> i then aux j
      else i in
  try
    aux i
  with GetoptFailure _ as exn ->
    handle_exn args exn

let parse_all ?(i = 1) opts extra args =
  let nargs = Array.length args in
  let rec aux i =
    if i = nargs then ()
    else
      let j = parse_one opts args i in
      if j <> i then aux j
      else if args.(i) = "--" then
        for i = i + 1 to nargs - 1 do
          extra args.(i)
        done
      else
        let () = extra args.(i) in
        aux (i + 1) in
  try
    aux i
  with GetoptFailure _ as exn ->
    handle_exn args exn
