(* Experimental module under development *)

exception Undetermined

open Mlmpfr_wrapper
type real = mpfr_float * mpfr_float
(* computationally, a real is represented as an interval of two floating-point numbers.
   such an interval `[a;b]` represents the set of real numbers between `a` and `b` *)

let init, set_exponents, get_prec, get_zero, get_one =
(*
   By default, for approximating real numbers, let's use binary128 floats
*)
  let emin = ref (-16493) in
  let emax = ref 16384 in
  let prec = ref 113 in
  let zero = ref (make_zero ~prec:!prec Positive) in
  let one = ref (make_from_int ~prec:!prec ~rnd:Toward_Minus_Infinity 1) in
  (fun emin_i emax_i prec_i ->
    emin := emin_i;
    emax := emax_i;
    prec := prec_i),
  (fun () ->
    set_emin !emin;
    set_emax !emax),
  (fun () -> !prec),
  (fun () -> !zero),
  (fun () -> !one)

let print_float fmt x =
  Format.fprintf fmt "%s" (get_formatted_str ~base:10 x)

let print_real fmt (x, y) =
  Format.fprintf fmt "[%a, %a]" print_float x print_float y


let add (xmin, xmax) (ymin, ymax) =
  (* Exponents can be changed if floats occur in the code. *)
  set_exponents ();
  let prec = get_prec () in
  let res_min = add ~prec ~rnd:Toward_Minus_Infinity xmin ymin in
  let res_max = add ~prec ~rnd:Toward_Plus_Infinity xmax ymax in
  (res_min, res_max)

let neg (xmin, xmax) =
  set_exponents ();
  let prec = get_prec () in
  let res_min = neg ~prec ~rnd:Toward_Minus_Infinity xmax in
  let res_max = neg ~prec ~rnd:Toward_Plus_Infinity xmin in
  (res_min, res_max)

let mul (xmin, xmax) (ymin, ymax) =
  set_exponents ();
  let prec = get_prec () in
  let min = min ~prec ~rnd:Toward_Minus_Infinity in
  let max = max ~prec ~rnd:Toward_Plus_Infinity in
  let mul1_min = mul ~prec ~rnd:Toward_Minus_Infinity xmin ymin in
  let mul2_min = mul ~prec ~rnd:Toward_Minus_Infinity xmin ymax in
  let mul3_min = mul ~prec ~rnd:Toward_Minus_Infinity xmax ymin in
  let mul4_min = mul ~prec ~rnd:Toward_Minus_Infinity xmax ymax in
  let res_min = List.fold_left min mul1_min [mul2_min; mul3_min; mul4_min] in
  let mul1_max = mul ~prec ~rnd:Toward_Plus_Infinity xmin ymin in
  let mul2_max = mul ~prec ~rnd:Toward_Plus_Infinity xmin ymax in
  let mul3_max = mul ~prec ~rnd:Toward_Plus_Infinity xmax ymin in
  let mul4_max = mul ~prec ~rnd:Toward_Plus_Infinity xmax ymax in
  let res_max = List.fold_left max mul1_max [mul2_max; mul3_max; mul4_max] in
  (res_min, res_max)

let inv (xmin, xmax) =
  set_exponents ();
  let prec = get_prec () in
  let zero = get_zero () in
  (* If 0 is inside the interval we cannot compute the expression *)
  if lessequal_p xmin zero && lessequal_p zero xmax then
    raise Undetermined
  else
    let one = get_one () in
    (* Inverse is decreasing on ]-inf; 0[ and on ]0; inf[ *)
    let res_min = div ~prec ~rnd:Toward_Minus_Infinity one xmax in
    let res_max = div ~prec ~rnd:Toward_Plus_Infinity one xmin in
    (res_min, res_max)

let div x y =
  mul x (inv y)

let sqrt (xmin, xmax) =
  set_exponents ();
  let prec = get_prec() in
  let zero = get_zero () in
  if lessequal_p zero xmin then
    let res_min = sqrt ~rnd:Toward_Minus_Infinity ~prec xmin in
    let res_max = sqrt ~rnd:Toward_Plus_Infinity ~prec xmax in
    (res_min, res_max)
  else
    raise Undetermined

let real_from_str s =
  let prec = get_prec () in
  let n1 = make_from_str ~prec ~base:10 ~rnd:Toward_Minus_Infinity s in
  let n2 = make_from_str ~prec ~base:10 ~rnd:Toward_Plus_Infinity s in
  (n1, n2)

let real_from_fraction p q =
  let p = real_from_str p in
  let q = real_from_str q in
  div p q

let eq (xmin, xmax) (ymin, ymax) =
  if less_p ymax xmin || less_p xmax ymin then
    (* Intervals are disjoint *)
    false
  else
    if (equal_p xmin xmax) && (equal_p ymin ymax) then
      (* Intervals are singleton and not disjoint, hence are equal *)
      true
    else
      raise Undetermined

let lt (x1,x2) (y1,y2) =
  if less_p x2 y1 then true else
    if lessequal_p y2 x1 then false else
      raise Undetermined

let le (x1,x2) (y1,y2) =
  if lessequal_p x2 y1 then true else
    if less_p y2 x1 then false else
      raise Undetermined

let gt x y = lt y x

let ge x y = le y x

let pi () =
  let prec = get_prec () in
  (const_pi ~rnd:Toward_Minus_Infinity prec,
   const_pi ~rnd:Toward_Plus_Infinity prec)
