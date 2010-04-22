(**************************************************************************)
(*                                                                        *)
(*  Copyright (C) 2010-                                                   *)
(*    Francois Bobot                                                      *)
(*    Jean-Christophe Filliatre                                           *)
(*    Johannes Kanig                                                      *)
(*    Andrei Paskevich                                                    *)
(*                                                                        *)
(*  This software is free software; you can redistribute it and/or        *)
(*  modify it under the terms of the GNU Library General Public           *)
(*  License version 2.1, with the special exception on linking            *)
(*  described in file LICENSE.                                            *)
(*                                                                        *)
(*  This software is distributed in the hope that it will be useful,      *)
(*  but WITHOUT ANY WARRANTY; without even the implied warranty of        *)
(*  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.                  *)
(*                                                                        *)
(**************************************************************************)

open Env
open Task
open Trans

type 'a trans_reg
type 'a tlist_reg = 'a list trans_reg

type clone = Theory.clone_map
type use = Theory.use_map

val store       : (unit ->                        'a trans) -> 'a trans_reg
val store_env   : (unit -> env ->                 'a trans) -> 'a trans_reg
val store_clone : (unit -> env -> clone        -> 'a trans) -> 'a trans_reg
val store_use   : (unit -> env -> use          -> 'a trans) -> 'a trans_reg
val store_both  : (unit -> env -> use -> clone -> 'a trans) -> 'a trans_reg
val store_task  : (unit -> env -> task         -> 'a trans) -> 'a trans_reg

exception ArgumentNeeded

val apply_env : 'a trans_reg -> env -> task -> 'a
val apply     : 'a trans_reg ->        task -> 'a

val compose   : task trans_reg -> 'a trans_reg -> 'a trans_reg
val compose_l : task tlist_reg -> 'a tlist_reg -> 'a tlist_reg
  (** Composition of transformations [compose f g] is the transformation
      which applies f before applying g *)


(* Should be only used with functions working in constant time *)
(* val conv_res : ('a -> 'b) -> 'a trans_reg -> 'b trans_reg *)

val singleton : 'a trans_reg -> 'a tlist_reg

val clear : 'a trans_reg -> unit

val identity   : task trans_reg
val identity_l : task tlist_reg

