(********************************************************************)
(*                                                                  *)
(*  The Why3 Verification Platform   /   The Why3 Development Team  *)
(*  Copyright 2010-2017   --   INRIA - CNRS - Paris-Sud University  *)
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
Require HighOrd.
Require map.Map.
Require map.Const.

Require Import ClassicalEpsilon.

Lemma predicate_extensionality:
  forall A (P Q : A -> bool),
    (forall x, P x = Q x) -> P = Q.
Admitted.

(* Why3 assumption *)
Definition set (a:Type) := (a -> bool).

Global Instance set_WhyType : forall (a:Type) {a_WT:WhyType a}, WhyType (set a).
Proof.
intros.
split.
exact (fun _ => false).
intros x y.
apply excluded_middle_informative.
Qed.

(* Why3 assumption *)
Definition mem {a:Type} {a_WT:WhyType a} (x:a) (s:(a -> bool)): Prop := ((s
  x) = true).

Hint Unfold mem.

(* Why3 assumption *)
Definition infix_eqeq {a:Type} {a_WT:WhyType a} (s1:(a -> bool)) (s2:(a ->
  bool)): Prop := forall (x:a), (mem x s1) <-> (mem x s2).

Notation "x == y" := (infix_eqeq x y) (at level 70, no associativity).

(* Why3 goal *)
Lemma extensionality : forall {a:Type} {a_WT:WhyType a}, forall (s1:(a ->
  bool)) (s2:(a -> bool)), (infix_eqeq s1 s2) -> (s1 = s2).
Proof.
intros a a_WT s1 s2 h1.
apply predicate_extensionality.
intros x.
generalize (h1 x).
unfold mem.
intros [h2 h3].
destruct (s1 x).
now rewrite h2.
destruct (s2 x).
now apply h3.
easy.
Qed.

(* Why3 assumption *)
Definition subset {a:Type} {a_WT:WhyType a} (s1:(a -> bool)) (s2:(a ->
  bool)): Prop := forall (x:a), (mem x s1) -> (mem x s2).

(* Why3 goal *)
Lemma subset_refl : forall {a:Type} {a_WT:WhyType a}, forall (s:(a -> bool)),
  (subset s s).
Proof.
now intros a a_WT s x.
Qed.

(* Why3 goal *)
Lemma subset_trans : forall {a:Type} {a_WT:WhyType a}, forall (s1:(a ->
  bool)) (s2:(a -> bool)) (s3:(a -> bool)), (subset s1 s2) -> ((subset s2
  s3) -> (subset s1 s3)).
Proof.
intros a a_WT s1 s2 s3 h1 h2 x H.
now apply h2, h1.
Qed.

(* Why3 assumption *)
Definition is_empty {a:Type} {a_WT:WhyType a} (s:(a -> bool)): Prop :=
  forall (x:a), ~ (mem x s).

(* Why3 goal *)
Lemma mem_empty : forall {a:Type} {a_WT:WhyType a}, (is_empty
  (map.Const.const false: (a -> bool))).
Proof.
now intros a a_WT x.
Qed.

(* Why3 goal *)
Lemma add_spec : forall {a:Type} {a_WT:WhyType a}, forall (x:a) (s:(a ->
  bool)), forall (y:a), (mem y (map.Map.set s x true)) <-> ((y = x) \/ (mem y
  s)).
Proof.
intros a a_WT x y s.
unfold Map.set, mem.
destruct why_decidable_eq ; intuition.
Qed.

(* Why3 goal *)
Lemma remove_spec : forall {a:Type} {a_WT:WhyType a}, forall (x:a) (s:(a ->
  bool)), forall (y:a), (mem y (map.Map.set s x false)) <-> ((~ (y = x)) /\
  (mem y s)).
Proof.
intros a a_WT x s y.
unfold Map.set, mem.
destruct why_decidable_eq ; intuition.
Qed.

(* Why3 goal *)
Lemma add_remove : forall {a:Type} {a_WT:WhyType a}, forall (x:a) (s:(a ->
  bool)), (mem x s) -> ((map.Map.set (map.Map.set s x false) x true) = s).
Proof.
intros a a_WT x s h1.
apply extensionality; intro y.
rewrite add_spec.
rewrite remove_spec.
destruct (why_decidable_eq y x) as [->|H] ; intuition.
Qed.

(* Why3 goal *)
Lemma remove_add : forall {a:Type} {a_WT:WhyType a}, forall (x:a) (s:(a ->
  bool)), ((map.Map.set (map.Map.set s x true) x false) = (map.Map.set s x
  false)).
Proof.
intros a a_WT x s.
apply extensionality; intro y.
rewrite remove_spec.
rewrite remove_spec.
rewrite add_spec.
destruct (why_decidable_eq y x) as [->|H] ; intuition.
Qed.

(* Why3 goal *)
Lemma subset_remove : forall {a:Type} {a_WT:WhyType a}, forall (x:a) (s:(a ->
  bool)), (subset (map.Map.set s x false) s).
Proof.
intros a a_WT x s y.
rewrite remove_spec.
now intros [_ H].
Qed.

(* Why3 goal *)
Definition union: forall {a:Type} {a_WT:WhyType a}, (a -> bool) -> (a ->
  bool) -> (a -> bool).
Proof.
intros a a_WT s1 s2.
exact (fun x => orb (s1 x) (s2 x)).
Defined.

(* Why3 goal *)
Lemma union_spec : forall {a:Type} {a_WT:WhyType a}, forall (s1:(a -> bool))
  (s2:(a -> bool)), forall (x:a), (mem x (union s1 s2)) <-> ((mem x s1) \/
  (mem x s2)).
Proof.
intros a a_WT s1 s2 x.
apply Bool.orb_true_iff.
Qed.

(* Why3 goal *)
Definition inter: forall {a:Type} {a_WT:WhyType a}, (a -> bool) -> (a ->
  bool) -> (a -> bool).
Proof.
intros a a_WT s1 s2.
exact (fun x => andb (s1 x) (s2 x)).
Defined.

(* Why3 goal *)
Lemma inter_spec : forall {a:Type} {a_WT:WhyType a}, forall (s1:(a -> bool))
  (s2:(a -> bool)), forall (x:a), (mem x (inter s1 s2)) <-> ((mem x s1) /\
  (mem x s2)).
Proof.
intros a a_WT s1 s2 x.
apply Bool.andb_true_iff.
Qed.

(* Why3 goal *)
Definition diff: forall {a:Type} {a_WT:WhyType a}, (a -> bool) -> (a ->
  bool) -> (a -> bool).
Proof.
intros a a_WT s1 s2.
exact (fun x => andb (s1 x) (negb (s2 x))).
Defined.

(* Why3 goal *)
Lemma diff_spec : forall {a:Type} {a_WT:WhyType a}, forall (s1:(a -> bool))
  (s2:(a -> bool)), forall (x:a), (mem x (diff s1 s2)) <-> ((mem x s1) /\
  ~ (mem x s2)).
Proof.
intros a a_WT s1 s2 x.
unfold mem, diff.
rewrite Bool.not_true_iff_false.
rewrite <- Bool.negb_true_iff.
apply Bool.andb_true_iff.
Qed.

(* Why3 goal *)
Lemma subset_diff : forall {a:Type} {a_WT:WhyType a}, forall (s1:(a -> bool))
  (s2:(a -> bool)), (subset (diff s1 s2) s1).
Proof.
intros a a_WT s1 s2 x.
rewrite diff_spec.
now intros [H _].
Qed.

(* Why3 goal *)
Definition complement: forall {a:Type} {a_WT:WhyType a}, (a -> bool) -> (a ->
  bool).
Proof.
intros a a_WT s.
exact (fun x => negb (s x)).
Defined.

(* Why3 goal *)
Lemma complement_def : forall {a:Type} {a_WT:WhyType a}, forall (s:(a ->
  bool)), forall (x:a), (((complement s) x) = true) <-> ~ ((s x) = true).
Proof.
intros a a_WT s x.
unfold complement.
rewrite Bool.not_true_iff_false.
apply Bool.negb_true_iff.
Qed.

(* Why3 goal *)
Definition choose: forall {a:Type} {a_WT:WhyType a}, (a -> bool) -> a.
Proof.
intros a a_WT s.
assert (i: inhabited a) by (apply inhabits, why_inhabitant).
exact (epsilon i (fun x => mem x s)).
Defined.

(* Why3 goal *)
Lemma choose_spec : forall {a:Type} {a_WT:WhyType a}, forall (s:(a -> bool)),
  (~ (is_empty s)) -> (mem (choose s) s).
Proof.
intros a a_WT s h1.
unfold choose.
apply epsilon_spec.
now apply not_all_not_ex.
Qed.

