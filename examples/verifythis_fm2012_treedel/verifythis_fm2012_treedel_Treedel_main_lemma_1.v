(* This file is generated by Why3's Coq driver *)
(* Beware! Only edit allowed sections below    *)
Require Import BuiltIn.
Require BuiltIn.
Require map.Map.
Require int.Int.

(* Why3 assumption *)
Definition unit := unit.

(* Why3 assumption *)
Inductive ref (a:Type) {a_WT:WhyType a} :=
  | mk_ref : a -> ref a.
Axiom ref_WhyType : forall (a:Type) {a_WT:WhyType a}, WhyType (ref a).
Existing Instance ref_WhyType.
Implicit Arguments mk_ref [[a] [a_WT]].

(* Why3 assumption *)
Definition contents {a:Type} {a_WT:WhyType a} (v:(ref a)): a :=
  match v with
  | (mk_ref x) => x
  end.

Axiom pointer : Type.
Parameter pointer_WhyType : WhyType pointer.
Existing Instance pointer_WhyType.

Parameter null: pointer.

(* Why3 assumption *)
Inductive node :=
  | mk_node : pointer -> pointer -> Z -> node.
Axiom node_WhyType : WhyType node.
Existing Instance node_WhyType.

(* Why3 assumption *)
Definition data (v:node): Z := match v with
  | (mk_node x x1 x2) => x2
  end.

(* Why3 assumption *)
Definition right1 (v:node): pointer :=
  match v with
  | (mk_node x x1 x2) => x1
  end.

(* Why3 assumption *)
Definition left1 (v:node): pointer :=
  match v with
  | (mk_node x x1 x2) => x
  end.

(* Why3 assumption *)
Definition memory := (map.Map.map pointer node).

(* Why3 assumption *)
Inductive tree
  (a:Type) {a_WT:WhyType a} :=
  | Empty : tree a
  | Node : (tree a) -> a -> (tree a) -> tree a.
Axiom tree_WhyType : forall (a:Type) {a_WT:WhyType a}, WhyType (tree a).
Existing Instance tree_WhyType.
Implicit Arguments Empty [[a] [a_WT]].
Implicit Arguments Node [[a] [a_WT]].

(* Why3 assumption *)
Inductive list
  (a:Type) {a_WT:WhyType a} :=
  | Nil : list a
  | Cons : a -> (list a) -> list a.
Axiom list_WhyType : forall (a:Type) {a_WT:WhyType a}, WhyType (list a).
Existing Instance list_WhyType.
Implicit Arguments Nil [[a] [a_WT]].
Implicit Arguments Cons [[a] [a_WT]].

(* Why3 assumption *)
Fixpoint infix_plpl {a:Type} {a_WT:WhyType a} (l1:(list a)) (l2:(list
  a)) {struct l1}: (list a) :=
  match l1 with
  | Nil => l2
  | (Cons x1 r1) => (Cons x1 (infix_plpl r1 l2))
  end.

Axiom Append_assoc : forall {a:Type} {a_WT:WhyType a}, forall (l1:(list a))
  (l2:(list a)) (l3:(list a)), ((infix_plpl l1 (infix_plpl l2
  l3)) = (infix_plpl (infix_plpl l1 l2) l3)).

Axiom Append_l_nil : forall {a:Type} {a_WT:WhyType a}, forall (l:(list a)),
  ((infix_plpl l (Nil :(list a))) = l).

(* Why3 assumption *)
Fixpoint length {a:Type} {a_WT:WhyType a} (l:(list a)) {struct l}: Z :=
  match l with
  | Nil => 0%Z
  | (Cons _ r) => (1%Z + (length r))%Z
  end.

Axiom Length_nonnegative : forall {a:Type} {a_WT:WhyType a}, forall (l:(list
  a)), (0%Z <= (length l))%Z.

Axiom Length_nil : forall {a:Type} {a_WT:WhyType a}, forall (l:(list a)),
  ((length l) = 0%Z) <-> (l = (Nil :(list a))).

Axiom Append_length : forall {a:Type} {a_WT:WhyType a}, forall (l1:(list a))
  (l2:(list a)), ((length (infix_plpl l1
  l2)) = ((length l1) + (length l2))%Z).

(* Why3 assumption *)
Fixpoint mem {a:Type} {a_WT:WhyType a} (x:a) (l:(list a)) {struct l}: Prop :=
  match l with
  | Nil => False
  | (Cons y r) => (x = y) \/ (mem x r)
  end.

Axiom mem_append : forall {a:Type} {a_WT:WhyType a}, forall (x:a) (l1:(list
  a)) (l2:(list a)), (mem x (infix_plpl l1 l2)) <-> ((mem x l1) \/ (mem x
  l2)).

Axiom mem_decomp : forall {a:Type} {a_WT:WhyType a}, forall (x:a) (l:(list
  a)), (mem x l) -> exists l1:(list a), exists l2:(list a),
  (l = (infix_plpl l1 (Cons x l2))).

(* Why3 assumption *)
Fixpoint inorder {a:Type} {a_WT:WhyType a} (t:(tree a)) {struct t}: (list
  a) :=
  match t with
  | Empty => (Nil :(list a))
  | (Node l x r) => (infix_plpl (inorder l) (Cons x (inorder r)))
  end.

(* Why3 assumption *)
Inductive distinct{a:Type} {a_WT:WhyType a}  : (list a) -> Prop :=
  | distinct_zero : (distinct (Nil :(list a)))
  | distinct_one : forall (x:a), (distinct (Cons x (Nil :(list a))))
  | distinct_many : forall (x:a) (l:(list a)), (~ (mem x l)) -> ((distinct
      l) -> (distinct (Cons x l))).

Axiom distinct_append : forall {a:Type} {a_WT:WhyType a}, forall (l1:(list
  a)) (l2:(list a)), (distinct l1) -> ((distinct l2) -> ((forall (x:a), (mem
  x l1) -> ~ (mem x l2)) -> (distinct (infix_plpl l1 l2)))).

(* Why3 assumption *)
Inductive tree1 : (map.Map.map pointer node) -> pointer -> (tree
  pointer) -> Prop :=
  | leaf : forall (m:(map.Map.map pointer node)), (tree1 m null (Empty :(tree
      pointer)))
  | node1 : forall (m:(map.Map.map pointer node)) (p:pointer) (l:(tree
      pointer)) (r:(tree pointer)), (~ (p = null)) -> ((tree1 m
      (left1 (map.Map.get m p)) l) -> ((tree1 m (right1 (map.Map.get m p))
      r) -> (tree1 m p (Node l p r)))).

(* Why3 assumption *)
Inductive zipper
  (a:Type) {a_WT:WhyType a} :=
  | Top : zipper a
  | Left : (zipper a) -> a -> (tree a) -> zipper a.
Axiom zipper_WhyType : forall (a:Type) {a_WT:WhyType a}, WhyType (zipper a).
Existing Instance zipper_WhyType.
Implicit Arguments Top [[a] [a_WT]].
Implicit Arguments Left [[a] [a_WT]].

(* Why3 assumption *)
Fixpoint zip {a:Type} {a_WT:WhyType a} (t:(tree a)) (z:(zipper
  a)) {struct z}: (tree a) :=
  match z with
  | Top => t
  | (Left z1 x r) => (zip (Node t x r) z1)
  end.

Axiom inorder_zip : forall {a:Type} {a_WT:WhyType a}, forall (z:(zipper a))
  (x:a) (l:(tree a)) (r:(tree a)), ((inorder (zip (Node l x r)
  z)) = (infix_plpl (inorder l) (Cons x (inorder (zip r z))))).

(** The proof starts here *)

Require Import Why3.
Ltac ae := why3 "Alt-Ergo,0.95," timelimit 3.

Lemma distinct1:
  forall (p pp: pointer) (pr ppr: tree pointer),
    distinct (Cons p (infix_plpl (inorder pr) (Cons pp (inorder ppr)))) ->
    p <> pp.
  Proof.
    induction pr; simpl; ae.
  Qed.

Lemma distinct2:
  forall m p p' n t, 
    let m' := Map.set m p' n in
    tree1 m p t -> ~ (mem p' (inorder t)) -> tree1 m' p t.
  Proof.
    induction 1; simpl.
    ae.
    intro.
    assert (~ (mem p' (inorder l))) by ae.
    assert (~ (mem p' (inorder r))) by ae.
    intuition.
    apply node1; subst m'.
    red; intro; elim H; trivial.
    ae.
    ae.
  Qed.

Lemma distinct3:
  forall (pp: pointer) (l1 l2: list pointer),
  distinct (infix_plpl l1 (Cons pp l2)) -> ~ (mem pp l1).
Proof.
induction l1; simpl; ae.
Qed.

Lemma distinct4:
  forall (pp: pointer) (l1 l2: list pointer),
  distinct (infix_plpl l1 (Cons pp l2)) -> ~ (mem pp l2).
Proof.
induction l1; simpl; ae.
Qed.

Lemma distinct_append1:
  forall (l1 l2: list pointer), distinct (infix_plpl l1 l2) -> distinct l1.
Proof.
  induction l1; simpl; ae.
Qed.

Lemma distinct5:
  forall z (p: pointer) (l r: tree pointer),
  distinct (inorder (zip (Node l p r) z)) -> distinct (inorder (Node l p r)).
Proof.
induction z.
ae.
intros.
simpl in H.
generalize (IHz a (Node l p r) t); clear IHz.
ae.
Qed.

Lemma tree1_zip:
  forall m t z l r pp,
  tree1 m t (zip (Node l pp r) z) -> tree1 m pp (Node l pp r).
Proof.
induction z; simpl.
ae.
inversion 1.
ae.
generalize (IHz (Node l pp r) t0 a).
ae.
Qed.

Lemma tree1_zip_2:
  forall m n a z t pp l r tr',
  tree1 m t (zip (Node l pp r) z) ->
  distinct (inorder (zip (Node l pp r) z)) ->
  mem a (inorder (Node l pp r)) -> let m' := Map.set m a n in
  tree1 m' pp tr' ->
  tree1 m' t (zip tr' z).
Proof.
induction z; simpl.
ae.
intros t0 pp l r tr'.
generalize (IHz t0 a0 (Node l pp r) t (Node tr' a0 t)); clear IHz; intros IHz.
intuition.
apply H4.
ae.
assert (a <> a0) by ae.
apply node1.
why3 "cvc3".
assert (left1 (Map.get (Map.set m a n) a0) = pp).
rewrite Map.Select_neq.
  generalize (tree1_zip _ _ _ _ _ _ H).
  inversion 1.
  inversion H11; auto.
assumption.
ae.
assert (right1 (Map.get (Map.set m a n) a0) = right1 (Map.get m a0)).
rewrite Map.Select_neq.
  generalize (tree1_zip _ _ _ _ _ _ H).
  inversion 1.
  inversion H11; auto.
assumption.
rewrite H5; clear H5.
apply distinct2.
generalize (tree1_zip _ _ _ _ _ _ H).
inversion 1.
ae.
clear H4 H2 H H3.
assert (mem a (inorder (Node l pp r))) by ae.
clear H1.
generalize (Node l pp r) H0 H. clear H0 H.
intros.
generalize (distinct5 _ _ _ _ H0); clear H0.
simpl.
intro.
assert (~ (mem a (Cons a0 (inorder t)))).
  generalize (inorder t1) H H0. clear H H0.
  generalize  (Cons a0 (inorder t)).
  ae.
ae.
Qed.

(* Why3 goal *)
Theorem main_lemma : forall (m:(map.Map.map pointer node)) (t:pointer)
  (pp:pointer) (p:pointer) (ppr:(tree pointer)) (pr:(tree pointer))
  (z:(zipper pointer)), let it := (zip (Node (Node (Empty :(tree pointer)) p
  pr) pp ppr) z) in ((tree1 m t it) -> ((distinct (inorder it)) -> (tree1
  (map.Map.set m pp (mk_node (right1 (map.Map.get m p))
  (right1 (map.Map.get m pp)) (data (map.Map.get m pp)))) t (zip (Node pr pp
  ppr) z)))).
intros m t pp p ppr pr z it h1 h2.
pose (m' := (Map.set m pp
     (mk_node (right1 (Map.get m p)) (right1 (Map.get m pp))
        (data (Map.get m pp))))).
assert (tree1 m' pp (Node pr pp ppr)).
assert (tree1 m pp (Node (Node (Empty:tree pointer) p pr) pp ppr)) by ae.
assert (tree1 m' pp (Node pr pp ppr)).
inversion H; simpl.
apply node1.
assumption.
unfold m'.
rewrite Map.Select_eq. 2: trivial.
unfold left1; simpl.
inversion H5.
rewrite -> H8 in *; clear H8.
rewrite <- H11 in *.
subst p1.
assert (p <> pp) by why3 "cvc3" timelimit 3.
apply distinct2.
ae.
why3 "cvc3" timelimit 3.
apply distinct2.
ae.
why3 "cvc3" timelimit 3.
assumption.
Print tree1_zip_2.
apply tree1_zip_2 with (l := (Node (Empty:tree pointer) p pr)) (r := ppr)
  (pp := pp); try
assumption.
ae.
Qed.


