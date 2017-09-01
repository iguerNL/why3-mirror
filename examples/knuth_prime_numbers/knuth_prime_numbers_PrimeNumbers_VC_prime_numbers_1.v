(* This file is generated by Why3's Coq driver *)
(* Beware! Only edit allowed sections below    *)
Require Import BuiltIn.
Require BuiltIn.
Require HighOrd.
Require int.Int.
Require int.Abs.
Require int.EuclideanDivision.
Require int.ComputerDivision.
Require number.Parity.
Require number.Divisibility.
Require number.Prime.
Require map.Map.

(* Why3 assumption *)
Definition lt_nat (x:Z) (y:Z): Prop := (0%Z <= y)%Z /\ (x < y)%Z.

(* Why3 assumption *)
Inductive lex: (Z* Z)%type -> (Z* Z)%type -> Prop :=
  | Lex_1 : forall (x1:Z) (x2:Z) (y1:Z) (y2:Z), (lt_nat x1 x2) -> (lex (x1,
      y1) (x2, y2))
  | Lex_2 : forall (x:Z) (y1:Z) (y2:Z), (lt_nat y1 y2) -> (lex (x, y1) (x,
      y2)).

(* Why3 assumption *)
Inductive ref (a:Type) :=
  | mk_ref : a -> ref a.
Axiom ref_WhyType : forall (a:Type) {a_WT:WhyType a}, WhyType (ref a).
Existing Instance ref_WhyType.
Implicit Arguments mk_ref [[a]].

(* Why3 assumption *)
Definition contents {a:Type} {a_WT:WhyType a} (v:(ref a)): a :=
  match v with
  | (mk_ref x) => x
  end.

(* Why3 assumption *)
Definition no_prime_in (l:Z) (u:Z): Prop := forall (x:Z), ((l < x)%Z /\
  (x < u)%Z) -> ~ (number.Prime.prime x).

(* Why3 assumption *)
Definition first_primes (p:(Z -> Z)) (u:Z): Prop := ((p 0%Z) = 2%Z) /\
  ((forall (i:Z) (j:Z), ((0%Z <= i)%Z /\ ((i < j)%Z /\ (j < u)%Z)) -> ((p
  i) < (p j))%Z) /\ ((forall (i:Z), ((0%Z <= i)%Z /\ (i < u)%Z) ->
  (number.Prime.prime (p i))) /\ forall (i:Z), ((0%Z <= i)%Z /\
  (i < (u - 1%Z)%Z)%Z) -> (no_prime_in (p i) (p (i + 1%Z)%Z)))).

Axiom exists_prime : forall (p:(Z -> Z)) (u:Z), (1%Z <= u)%Z ->
  ((first_primes p u) -> forall (d:Z), ((2%Z <= d)%Z /\ (d <= (p
  (u - 1%Z)%Z))%Z) -> ((number.Prime.prime d) -> exists i:Z, ((0%Z <= i)%Z /\
  (i < u)%Z) /\ (d = (p i)))).

Axiom Bertrand_postulate : forall (p:Z), (number.Prime.prime p) ->
  ~ (no_prime_in p (2%Z * p)%Z).

Axiom array : forall (a:Type), Type.
Parameter array_WhyType : forall (a:Type) {a_WT:WhyType a},
  WhyType (array a).
Existing Instance array_WhyType.

Parameter elts: forall {a:Type} {a_WT:WhyType a}, (array a) -> (Z -> a).

Parameter length: forall {a:Type} {a_WT:WhyType a}, (array a) -> Z.

Axiom array'invariant : forall {a:Type} {a_WT:WhyType a}, forall (self:(array
  a)), (0%Z <= (length self))%Z.

(* Why3 assumption *)
Definition mixfix_lbrb {a:Type} {a_WT:WhyType a} (a1:(array a)) (i:Z): a :=
  ((elts a1) i).

Parameter mixfix_lblsmnrb: forall {a:Type} {a_WT:WhyType a}, (array a) ->
  Z -> a -> (array a).

Axiom mixfix_lblsmnrb_spec : forall {a:Type} {a_WT:WhyType a},
  forall (a1:(array a)) (i:Z) (v:a), ((length (mixfix_lblsmnrb a1 i
  v)) = (length a1)) /\ ((elts (mixfix_lblsmnrb a1 i
  v)) = (map.Map.set (elts a1) i v)).

(* Why3 goal *)
Theorem VC_prime_numbers : forall (m:Z), (2%Z <= m)%Z -> forall (p:(array
  Z)), ((forall (i:Z), ((0%Z <= i)%Z /\ (i < m)%Z) -> ((mixfix_lbrb p
  i) = 0%Z)) /\ ((length p) = m)) -> forall (p1:(array Z)),
  ((length p1) = (length p)) -> (((elts p1) = (map.Map.set (elts p) 0%Z
  2%Z)) -> forall (p2:(array Z)), ((length p2) = (length p1)) ->
  (((elts p2) = (map.Map.set (elts p1) 1%Z 3%Z)) -> let o := (m - 1%Z)%Z in
  ((2%Z <= (o + 1%Z)%Z)%Z -> forall (n:Z) (p3:(array Z)),
  ((length p3) = (length p2)) -> forall (j:Z), (((2%Z <= j)%Z /\
  (j <= o)%Z) /\ ((first_primes (elts p3) j) /\ ((((mixfix_lbrb p3
  (j - 1%Z)%Z) < n)%Z /\ (n < (2%Z * (mixfix_lbrb p3 (j - 1%Z)%Z))%Z)%Z) /\
  ((number.Parity.odd n) /\ (no_prime_in (mixfix_lbrb p3 (j - 1%Z)%Z)
  n))))) -> forall (n1:Z) (p4:(array Z)), ((length p4) = (length p3)) ->
  forall (k:Z), (((1%Z <= k)%Z /\ (k < j)%Z) /\ ((first_primes (elts p4)
  j) /\ ((((mixfix_lbrb p4 (j - 1%Z)%Z) < n1)%Z /\
  (n1 < (2%Z * (mixfix_lbrb p4 (j - 1%Z)%Z))%Z)%Z) /\ ((number.Parity.odd
  n1) /\ ((no_prime_in (mixfix_lbrb p4 (j - 1%Z)%Z) n1) /\ forall (i:Z),
  ((0%Z <= i)%Z /\ (i < k)%Z) -> ~ (number.Divisibility.divides
  (mixfix_lbrb p4 i) n1)))))) -> (((ZArith.BinInt.Z.rem n1 (mixfix_lbrb p4
  k)) = 0%Z) -> ((~ (number.Prime.prime n1)) -> forall (n2:Z),
  (n2 = (n1 + 2%Z)%Z) -> (((1%Z <= 1%Z)%Z /\ (1%Z < j)%Z) -> ((first_primes
  (elts p4) j) -> (n2 < (2%Z * (mixfix_lbrb p4 (j - 1%Z)%Z))%Z)%Z))))))).
Proof.
intros m h1 p (h2,h3) p1 h4 h5 p2 h6 h7 o h8 n p3 h9 j
((h10,h11),(h12,((h13,h14),(h15,h16)))) n1 p4 h17 k
((h18,h19),(h20,((h21,h22),(h23,(h24,h25))))) h26 h27 n2 h28 (h29,h30) h31.
assert (case: (n2 < 2 * elts p4 (j-1) \/ n2 >= 2 * elts p4 (j-1))%Z) by omega.
destruct case.
auto.
apply False_ind.
apply Bertrand_postulate with (elts p4 (j-1)%Z); intuition.
red in h20; decompose [and] h20; clear h20.
apply H1; omega.
red; intros.
assert (case: (x < n1 \/ x = n1 \/ x = n1+1)%Z) by omega. destruct case.
apply h24.
unfold mixfix_lbrb.
omega.
destruct H1; subst x.
intuition.
intro K.
apply Prime.even_prime in K.
omega.
now apply Parity.odd_even.
Qed.

