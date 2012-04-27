(* This file is generated by Why3's Coq driver *)
(* Beware! Only edit allowed sections below    *)
Require Import ZArith.
Require Import Rbase.
Require int.Int.

Parameter pow2: Z -> Z.

Axiom Power_0 : ((pow2 0%Z) = 1%Z).

Axiom Power_s : forall (n:Z), (0%Z <= n)%Z ->
  ((pow2 (n + 1%Z)%Z) = (2%Z * (pow2 n))%Z).

Axiom Power_1 : ((pow2 1%Z) = 2%Z).

Axiom Power_sum : forall (n:Z) (m:Z), ((0%Z <= n)%Z /\ (0%Z <= m)%Z) ->
  ((pow2 (n + m)%Z) = ((pow2 n) * (pow2 m))%Z).

Require Import Why3.
Ltac ae := why3 "alt-ergo" timelimit 2.
Open Scope Z_scope.

(* Why3 goal *)
Theorem pow2pos : forall (i:Z), (0%Z <= i)%Z -> (0%Z <  (pow2 i))%Z.
intros i Hi.
generalize Hi.
pattern i; apply Z_lt_induction; auto.
intros j Hind Hj.
assert (h: j=0 \/ j>0) by omega; destruct h.
ae.
replace j with ((j-1)+1) by omega.
ae.
Qed.


