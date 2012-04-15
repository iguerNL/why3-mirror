(* This file is generated by Why3's Coq driver *)
(* Beware! Only edit allowed sections below    *)
Require Import ZArith.
Require Import Rbase.
Require int.Int.

(* Why3 assumption *)
Definition unit  := unit.

Parameter qtmark : Type.

Parameter at1: forall (a:Type), a -> qtmark -> a.
Implicit Arguments at1.

Parameter old: forall (a:Type), a -> a.
Implicit Arguments old.

(* Why3 assumption *)
Definition implb(x:bool) (y:bool): bool := match (x,
  y) with
  | (true, false) => false
  | (_, _) => true
  end.

(* Why3 assumption *)
Inductive list (a:Type) :=
  | Nil : list a
  | Cons : a -> (list a) -> list a.
Set Contextual Implicit.
Implicit Arguments Nil.
Unset Contextual Implicit.
Implicit Arguments Cons.

(* Why3 assumption *)
Set Implicit Arguments.
Fixpoint infix_plpl (a:Type)(l1:(list a)) (l2:(list a)) {struct l1}: (list
  a) :=
  match l1 with
  | Nil => l2
  | (Cons x1 r1) => (Cons x1 (infix_plpl r1 l2))
  end.
Unset Implicit Arguments.

Axiom Append_assoc : forall (a:Type), forall (l1:(list a)) (l2:(list a))
  (l3:(list a)), ((infix_plpl l1 (infix_plpl l2
  l3)) = (infix_plpl (infix_plpl l1 l2) l3)).

Axiom Append_l_nil : forall (a:Type), forall (l:(list a)), ((infix_plpl l
  (Nil :(list a))) = l).

(* Why3 assumption *)
Set Implicit Arguments.
Fixpoint length (a:Type)(l:(list a)) {struct l}: Z :=
  match l with
  | Nil => 0%Z
  | (Cons _ r) => (1%Z + (length r))%Z
  end.
Unset Implicit Arguments.

Axiom Length_nonnegative : forall (a:Type), forall (l:(list a)),
  (0%Z <= (length l))%Z.

Axiom Length_nil : forall (a:Type), forall (l:(list a)),
  ((length l) = 0%Z) <-> (l = (Nil :(list a))).

Axiom Append_length : forall (a:Type), forall (l1:(list a)) (l2:(list a)),
  ((length (infix_plpl l1 l2)) = ((length l1) + (length l2))%Z).

(* Why3 assumption *)
Set Implicit Arguments.
Fixpoint mem (a:Type)(x:a) (l:(list a)) {struct l}: Prop :=
  match l with
  | Nil => False
  | (Cons y r) => (x = y) \/ (mem x r)
  end.
Unset Implicit Arguments.

Axiom mem_append : forall (a:Type), forall (x:a) (l1:(list a)) (l2:(list a)),
  (mem x (infix_plpl l1 l2)) <-> ((mem x l1) \/ (mem x l2)).

Axiom mem_decomp : forall (a:Type), forall (x:a) (l:(list a)), (mem x l) ->
  exists l1:(list a), exists l2:(list a), (l = (infix_plpl l1 (Cons x l2))).

(* Why3 assumption *)
Inductive tree  :=
  | Leaf : tree 
  | Node : tree -> tree -> tree .

(* Why3 assumption *)
Set Implicit Arguments.
Fixpoint depths(d:Z) (t:tree) {struct t}: (list Z) :=
  match t with
  | Leaf => (Cons d (Nil :(list Z)))
  | (Node l r) => (infix_plpl (depths (d + 1%Z)%Z l) (depths (d + 1%Z)%Z r))
  end.
Unset Implicit Arguments.

Axiom depths_head : forall (t:tree) (d:Z), match (depths d
  t) with
  | (Cons x _) => (d <= x)%Z
  | Nil => False
  end.

Axiom depths_unique : forall (t1:tree) (t2:tree) (d:Z) (s1:(list Z))
  (s2:(list Z)), ((infix_plpl (depths d t1) s1) = (infix_plpl (depths d t2)
  s2)) -> ((t1 = t2) /\ (s1 = s2)).

(* Why3 assumption *)
Definition lt_nat(x:Z) (y:Z): Prop := (0%Z <= y)%Z /\ (x <  y)%Z.

(* Why3 assumption *)
Inductive lex : (Z* Z)%type -> (Z* Z)%type -> Prop :=
  | Lex_1 : forall (x1:Z) (x2:Z) (y1:Z) (y2:Z), (lt_nat x1 x2) -> (lex (x1,
      y1) (x2, y2))
  | Lex_2 : forall (x:Z) (y1:Z) (y2:Z), (lt_nat y1 y2) -> (lex (x, y1) (x,
      y2)).

(* Why3 assumption *)
Set Implicit Arguments.
Fixpoint reverse (a:Type)(l:(list a)) {struct l}: (list a) :=
  match l with
  | Nil => (Nil :(list a))
  | (Cons x r) => (infix_plpl (reverse r) (Cons x (Nil :(list a))))
  end.
Unset Implicit Arguments.

Axiom reverse_append : forall (a:Type), forall (l1:(list a)) (l2:(list a))
  (x:a), ((infix_plpl (reverse (Cons x l1)) l2) = (infix_plpl (reverse l1)
  (Cons x l2))).

Axiom reverse_reverse : forall (a:Type), forall (l:(list a)),
  ((reverse (reverse l)) = l).

Axiom Reverse_length : forall (a:Type), forall (l:(list a)),
  ((length (reverse l)) = (length l)).

(* Why3 assumption *)
Set Implicit Arguments.
Fixpoint forest_depths(f:(list (Z* tree)%type)) {struct f}: (list Z) :=
  match f with
  | Nil => (Nil :(list Z))
  | (Cons (d, t) r) => (infix_plpl (depths d t) (forest_depths r))
  end.
Unset Implicit Arguments.

Require Import Why3. Ltac ae := why3 "alt-ergo".

(* Why3 goal *)
Theorem forest_depths_append : forall (f1:(list (Z* tree)%type)) (f2:(list
  (Z* tree)%type)), ((forest_depths (infix_plpl f1
  f2)) = (infix_plpl (forest_depths f1) (forest_depths f2))).
induction f1; simpl; auto.
(* BUG ae. *)
destruct a.
intro f2.
rewrite IHf1.
rewrite Append_assoc; auto.
Qed.


