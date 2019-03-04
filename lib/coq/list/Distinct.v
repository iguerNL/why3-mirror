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

(* This file is generated by Why3's Coq-realize driver *)
(* Beware! Only edit allowed sections below    *)
Require Import BuiltIn.
Require BuiltIn.
Require int.Int.
Require list.List.
Require list.Length.
Require list.Mem.
Require list.Append.

(* Why3 assumption *)
Inductive distinct {a:Type} {a_WT:WhyType a}: (list a) -> Prop :=
  | distinct_zero : distinct Init.Datatypes.nil
  | distinct_one :
      forall (x:a), distinct (Init.Datatypes.cons x Init.Datatypes.nil)
  | distinct_many :
      forall (x:a) (l:(list a)), ~ list.Mem.mem x l -> distinct l ->
      distinct (Init.Datatypes.cons x l).

(* Why3 goal *)
Lemma distinct_append {a:Type} {a_WT:WhyType a} :
  forall (l1:(list a)) (l2:(list a)), distinct l1 -> distinct l2 ->
  (forall (x:a), list.Mem.mem x l1 -> ~ list.Mem.mem x l2) ->
  distinct (Init.Datatypes.app l1 l2).
Proof.
intros l1 l2 h1 h2 h3.
induction l1 as [|l1h l1t IHl1].
exact h2.
simpl.
inversion h1 ; subst.
- apply distinct_many with (2 := h2).
  apply h3.
  now left.
- apply distinct_many.
  contradict H1.
  apply Append.mem_append in H1.
  destruct H1 as [H1|H1].
  exact H1.
  elim h3 with (2 := H1).
  now left.
  apply IHl1 with (1 := H2).
  intros x Hx.
  apply h3.
  now right.
Qed.

