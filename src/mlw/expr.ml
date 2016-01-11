(********************************************************************)
(*                                                                  *)
(*  The Why3 Verification Platform   /   The Why3 Development Team  *)
(*  Copyright 2010-2015   --   INRIA - CNRS - Paris-Sud University  *)
(*                                                                  *)
(*  This software is distributed under the terms of the GNU Lesser  *)
(*  General Public License version 2.1, with the special exception  *)
(*  on linking described in file LICENSE.                           *)
(*                                                                  *)
(********************************************************************)

open Stdlib
open Ident
open Ty
open Term
open Ity

(** {2 Routine symbols} *)

type rsymbol = {
  rs_name  : ident;
  rs_cty   : cty;
  rs_logic : rs_logic;
  rs_field : pvsymbol option;
}

and rs_logic =
  | RLnone            (* non-pure symbol *)
  | RLpv of pvsymbol  (* local let-function *)
  | RLls of lsymbol   (* top-level let-function or let-predicate *)
  | RLlemma           (* top-level or local let-lemma *)

module Rsym = MakeMSHW (struct
  type t = rsymbol
  let tag rs = rs.rs_name.id_tag
end)

module Srs = Rsym.S
module Mrs = Rsym.M
module Hrs = Rsym.H
module Wrs = Rsym.W

let rs_equal : rsymbol -> rsymbol -> bool = (==)
let rs_hash rs = id_hash rs.rs_name
let rs_compare rs1 rs2 = id_compare rs1.rs_name rs2.rs_name

let mk_rs, restore_rs =
  let ls_to_rs = Wls.create 17 in
  (fun id cty lg mf ->
    let rs = {
      rs_name  = id;
      rs_cty   = cty;
      rs_logic = lg;
      rs_field = mf;
    } in
    match lg with
    | RLls ls -> Wls.set ls_to_rs ls rs; rs
    | _ -> rs),
  (fun ls -> Wls.find ls_to_rs ls)

type rs_kind =
  | RKnone    (* non-pure symbol *)
  | RKlocal   (* local let-function *)
  | RKfunc    (* top-level let-function *)
  | RKpred    (* top-level let-predicate *)
  | RKlemma   (* top-level or local let-lemma *)

let rs_ghost s = s.rs_cty.cty_effect.eff_ghost

let check_effects ?loc c =
  if c.cty_effect.eff_oneway then Loc.errorm ?loc
    "This function may not terminate, it cannot be used as pure";
  if not (cty_pure c) then Loc.errorm ?loc
    "This function has side effects, it cannot be used as pure"

let check_reads ?loc c =
  if not (Spv.is_empty (cty_reads c)) then Loc.errorm ?loc
    "This function depends on external variables, it cannot be used as pure"

let check_state ?loc c =
  if not (Mreg.is_empty c.cty_freeze.isb_reg) then Loc.errorm ?loc
    "This function is stateful, it cannot be used as pure"

let cty_ghostify ?loc gh c = try cty_ghostify gh c with
  | BadGhostWrite (v,_) -> Loc.errorm ?loc
      "This ghost function modifies the non-ghost variable %a" print_pv v
  | GhostDivergence -> Loc.errorm ?loc
      "This ghost function may not terminate"

let cty_purify c =
  let add a ity = ity_func (ity_purify a.pv_ity) ity in
  List.fold_right add c.cty_args (ity_purify c.cty_result)

let make_post t = match t.t_ty with
  | Some ty ->
      let res = create_vsymbol (id_fresh "result") ty in
      create_post res (t_equ (t_var res) t)
  | None ->
      let res = create_vsymbol (id_fresh "result") ty_bool in
      create_post res (t_iff (t_equ (t_var res) t_bool_true) t)

let add_post c t = cty_add_post c [make_post t]

let create_rsymbol ({pre_loc=loc} as id) ?(ghost=false) ?(kind=RKnone) c =
  let arg_list c = List.map (fun a -> t_var a.pv_vs) c.cty_args in
  let arg_type c = List.map (fun a -> a.pv_vs.vs_ty) c.cty_args in
  let res_type c = ty_of_ity c.cty_result in
  let c = cty_ghostify ?loc ghost c in
  match kind with
  | RKnone ->
      mk_rs (id_register id) c RLnone None
  | RKlocal ->
      check_effects ?loc c; check_state ?loc c;
      (* When declaring local let-functions, we need to create a
         mapping vsymbol to use in assertions. As vsymbols are not
         generalisable, we have to freeze the type variables (but
         not regions) of the rsymbol, and the easiest way to do that
         is to make these type variables appear in (cty_reads c).
         Moreover, we want to maintain the invariant that every
         variable that occurs freely in an assertion comes from
         a pvsymbol. Therefore, we create a pvsymbol whose type
         is a snapshot of the appropriate mapping type, and put
         it into the rs_logic field. This pvsymbol should not be
         used in the program, as it has lost all preconditions,
         which is why we declare it as ghost. In other words,
         this pvsymbol behaves exactly as Epure of its pv_vs. *)
      let v = create_pvsymbol ~ghost:true id (cty_purify c) in
      let t = t_func_app_l (t_var v.pv_vs) (arg_list c) in
      mk_rs v.pv_vs.vs_name (add_post c t) (RLpv v) None
  | RKfunc ->
      check_effects ?loc c; check_reads ?loc c;
      let ls = create_fsymbol id (arg_type c) (res_type c) in
      let t = t_app ls (arg_list c) ls.ls_value in
      mk_rs ls.ls_name (add_post c t) (RLls ls) None
  | RKpred ->
      check_effects ?loc c; check_reads ?loc c;
      if not (ity_equal c.cty_result ity_bool) then Loc.errorm ?loc
        "This function returns a value of type %a, it cannot be \
          declared as a pure predicate" print_ity c.cty_result;
      let ls = create_psymbol id (arg_type c) in
      let f = t_app ls (arg_list c) None in
      mk_rs ls.ls_name (add_post c f) (RLls ls) None
  | RKlemma ->
      check_effects ?loc c;
      mk_rs (id_register id) c RLlemma None

let rs_dup ({rs_name = {id_loc = loc}} as s) c =
  let id = id_register (id_clone s.rs_name) in
  let c = cty_ghostify ?loc (rs_ghost s) c in
  match s.rs_logic with
  | RLnone ->
      mk_rs id c RLnone None
  | RLpv v ->
      check_effects ?loc c; check_state ?loc c;
      Loc.try2 ?loc ity_equal_check v.pv_ity (cty_purify c);
      let al = List.map (fun a -> t_var a.pv_vs) c.cty_args in
      let t = t_func_app_l (t_var v.pv_vs) al in
      mk_rs id (add_post c t) (RLpv v) None
  | RLls _ ->
      invalid_arg "Expr.rs_dup"
  | RLlemma ->
      check_effects ?loc c;
      mk_rs id c RLlemma None

let create_projection s v =
  let id = id_clone v.pv_vs.vs_name in
  let eff = eff_ghostify v.pv_ghost eff_empty in
  let tyl = List.map ity_var s.its_ts.ts_args in
  let rgl = List.map ity_reg s.its_regions in
  let ity = ity_app s tyl rgl in
  let arg = create_pvsymbol (id_fresh "arg") ity in
  let ls = create_fsymbol id [arg.pv_vs.vs_ty] v.pv_vs.vs_ty in
  let q = make_post (fs_app ls [t_var arg.pv_vs] v.pv_vs.vs_ty) in
  let c = create_cty [arg] [] [q] Mexn.empty Mpv.empty eff v.pv_ity in
  mk_rs ls.ls_name c (RLls ls) (Some v)

exception FieldExpected of rsymbol

let mfield_of_rs s = match s.rs_cty.cty_args, s.rs_field with
  | [{pv_ity = {ity_node = Ityreg {reg_its = its}}}], Some f
    when List.exists (pv_equal f) its.its_mfields -> f
  | _ -> raise (FieldExpected s)

let create_constructor ~constr id s fl =
  let exn = Invalid_argument "Expr.create_constructor" in
  let fs = List.fold_right (Spv.add_new exn) fl Spv.empty in
  if List.exists (fun f -> not (Spv.mem f fs)) s.its_mfields ||
    s.its_private || s.its_def <> None || constr < 1 ||
    (s.its_mutable && constr > 1) then raise exn;
  let argl = List.map (fun a -> a.pv_vs.vs_ty) fl in
  let tyl = List.map ity_var s.its_ts.ts_args in
  let rgl = List.map ity_reg s.its_regions in
  let ity = ity_app s tyl rgl in
  let ty = ty_of_ity ity in
  let ls = create_fsymbol ~constr id argl ty in
  let argl = List.map (fun a -> t_var a.pv_vs) fl in
  let q = make_post (fs_app ls argl ty) in
  let eff = match ity.ity_node with
    | Ityreg r -> eff_reset eff_empty (Sreg.singleton r)
    | _ -> eff_empty in
  let c = create_cty fl [] [q] Mexn.empty Mpv.empty eff ity in
  mk_rs ls.ls_name c (RLls ls) None

let rs_of_ls ls =
  let v_args = List.map (fun ty ->
    create_pvsymbol (id_fresh "u") (ity_of_ty ty)) ls.ls_args in
  let t_args = List.map (fun v -> t_var v.pv_vs) v_args in
  let q = make_post (t_app ls t_args ls.ls_value) in
  let ity = ity_of_ty (t_type q) in
  let c = create_cty v_args [] [q] Mexn.empty Mpv.empty eff_empty ity in
  mk_rs ls.ls_name c (RLls ls) None

(** {2 Program patterns} *)

type pat_ghost =
  | PGfail  (* refutable ghost subpattern before "|" *)
  | PGlast  (* refutable ghost subpattern otherwise  *)
  | PGnone  (* every ghost subpattern is irrefutable *)

type prog_pattern = {
  pp_pat  : pattern;    (* pure pattern *)
  pp_ity  : ity;        (* type of the matched value *)
  pp_mask : mask;       (* mask of the matched value *)
  pp_fail : pat_ghost;  (* refutable ghost subpattern *)
}

type pre_pattern =
  | PPwild
  | PPvar of preid * bool
  | PPapp of rsymbol * pre_pattern list
  | PPas  of pre_pattern * preid * bool
  | PPor  of pre_pattern * pre_pattern

exception ConstructorExpected of rsymbol

let create_prog_pattern pp ity mask =
  let fail = ref PGnone in
  let hg = Hstr.create 3 in
  let mark {pre_name = nm} gh mask =
    if gh || mask_ghost mask then Hstr.replace hg nm () in
  let rec scan gp mask = function
    | PPapp ({rs_logic = RLls ls} as rs, pl) when ls.ls_constr > 0 ->
        if mask = MaskGhost && ls.ls_constr > 1 && !fail <> PGfail
        then fail := gp; (* we do not replace PGfail with PGlast *)
        let ml = match mask with
          | MaskGhost -> List.map (Util.const MaskGhost) ls.ls_args
          | MaskVisible -> List.map mask_of_pv rs.rs_cty.cty_args
          | MaskTuple ml when is_fs_tuple ls &&
              List.length ls.ls_args = List.length ml -> ml
          | MaskTuple _ -> invalid_arg "Expr.create_prog_pattern" in
        (try List.iter2 (scan gp) ml pl with Invalid_argument _ ->
          raise (Term.BadArity (ls, List.length pl)))
    | PPapp (rs,_) -> raise (ConstructorExpected rs)
    | PPvar (id,gh) -> mark id gh mask
    | PPas (pp,id,gh) -> mark id gh mask; scan gp mask pp
    | PPor (pp1,pp2) -> scan PGfail mask pp1; scan gp mask pp2
    | PPwild -> () in
  scan PGlast mask pp;
  let hv = Hstr.create 3 in
  let find ({pre_name = nm} as id) ity =
    try let v = Hstr.find hv nm in
      ity_equal_check ity v.pv_ity; v.pv_vs
    with Not_found ->
      let v = create_pvsymbol id ~ghost:(Hstr.mem hg nm) ity in
      Hstr.add hv nm v; v.pv_vs in
  let rec make ity = function
    | PPapp ({rs_cty = cty; rs_logic = RLls ls}, ppl) ->
        let sbs = ity_match isb_empty cty.cty_result ity in
        let make arg pp = make (ity_full_inst sbs arg.pv_ity) pp in
        pat_app ls (List.map2 make cty.cty_args ppl) (ty_of_ity ity)
    | PPapp (rs,_) -> raise (ConstructorExpected rs)
    | PPvar (id,_) -> pat_var (find id ity)
    | PPas (pp,id,_) -> pat_as (make ity pp) (find id ity)
    | PPor (pp1,pp2) -> pat_or (make ity pp1) (make ity pp2)
    | PPwild -> pat_wild (ty_of_ity ity) in
  let pat = make ity pp in
  let mvs = Hstr.fold Mstr.add hv Mstr.empty in
  mvs, {pp_pat = pat; pp_ity = ity; pp_mask = mask; pp_fail = !fail}

(** {2 Program expressions} *)

type assertion_kind = Assert | Assume | Check

type for_direction = To | DownTo

type for_bounds = pvsymbol * for_direction * pvsymbol

type invariant = term

type variant = term * lsymbol option (** tau * (tau -> tau -> prop) *)

type assign = pvsymbol * rsymbol * pvsymbol (* region * field * value *)

type expr = {
  e_node   : expr_node;
  e_ity    : ity;
  e_mask   : mask;
  e_effect : effect;
  e_label  : Slab.t;
  e_loc    : Loc.position option;
}

and expr_node =
  | Evar    of pvsymbol
  | Econst  of Number.constant
  | Eexec   of cexp
  | Eassign of assign list
  | Elet    of let_defn * expr
  | Eif     of expr * expr * expr
  | Ecase   of expr * (prog_pattern * expr) list
  | Ewhile  of expr * invariant list * variant list * expr
  | Efor    of pvsymbol * for_bounds * invariant list * expr
  | Etry    of expr * (xsymbol * pvsymbol * expr) list
  | Eraise  of xsymbol * expr
  | Eassert of assertion_kind * term
  | Eghost  of expr
  | Epure   of term
  | Eabsurd

and cexp = {
  c_node : cexp_node;
  c_cty  : cty;
}

and cexp_node =
  | Capp of rsymbol * pvsymbol list
  | Cpur of lsymbol * pvsymbol list
  | Cfun of expr
  | Cany

and let_defn =
  | LDvar of pvsymbol * expr
  | LDsym of rsymbol * cexp
  | LDrec of rec_defn list

and rec_defn = {
  rec_sym  : rsymbol; (* exported symbol *)
  rec_rsym : rsymbol; (* internal symbol *)
  rec_fun  : cexp;    (* Cfun *)
  rec_varl : variant list;
}

(* basic tools *)

let e_label ?loc l e = { e with e_label = l; e_loc = loc }

let e_label_add l e = { e with e_label = Slab.add l e.e_label }

let e_label_copy { e_label = lab; e_loc = loc } e =
  let lab = Slab.union lab e.e_label in
  let loc = if e.e_loc = None then loc else e.e_loc in
  { e with e_label = lab; e_loc = loc }

let e_ghost e = e.e_effect.eff_ghost
let c_ghost c = c.c_cty.cty_effect.eff_ghost

(* e_fold never goes under cexps *)
let e_fold fn acc e = match e.e_node with
  | Evar _ | Econst _ | Eexec _ | Eassign _
  | Eassert _ | Epure _ | Eabsurd -> acc
  | Eraise (_,e) | Efor (_,_,_,e) | Eghost e
  | Elet ((LDsym _|LDrec _), e) -> fn acc e
  | Elet (LDvar (_,d), e) | Ewhile (d,_,_,e) -> fn (fn acc d) e
  | Eif (c,d,e) -> fn (fn (fn acc c) d) e
  | Ecase (d,bl) -> List.fold_left (fun acc (_,e) -> fn acc e) (fn acc d) bl
  | Etry (d,xl) -> List.fold_left (fun acc (_,_,e) -> fn acc e) (fn acc d) xl

exception FoundExpr of Loc.position option * expr

(* find a minimal sub-expression whose effect satisfies [pr] *)
let find_effect pr loc e =
  let rec find loc e =
    if not (pr e.e_effect) then loc else
    let loc = if e.e_loc = None then loc else e.e_loc in
    let loc = match e.e_node with
      | Eexec {c_node = Cfun d} -> find loc d
      | _ ->                e_fold find loc e in
    raise (FoundExpr (loc,e)) in
  try find loc e, e with FoundExpr (loc,e) -> loc, e

let e_locate_effect pr e = fst (find_effect pr None e)

(* localize an illegal ghost write *)
let localize_ghost_write v r el =
  let taints eff = Mreg.mem r eff.eff_taints in
  let writes eff = match Mreg.find_opt r eff.eff_writes with
    | Some fds -> r.reg_its.its_private ||
        Spv.exists (fun fd -> not fd.pv_ghost) fds
    | None -> false in
  (* check if some component taints region r *)
  List.iter (fun e -> if taints e.e_effect then
    let loc, e = find_effect taints None e in
    let loc, _ = find_effect writes loc e in
    Loc.error ?loc (BadGhostWrite (v,r))) el;
  (* we are ghostified, check if someone writes into r *)
  List.iter (fun e -> if writes e.e_effect then
    let loc = e_locate_effect writes e in
    Loc.error ?loc (BadGhostWrite (v,r))) el;
  raise (BadGhostWrite (v,r))

(* localize a write into an immutable position *)
let localize_immut_write v r el =
  let writes eff = Mreg.mem r eff.eff_writes in
  List.iter (fun e -> if writes e.e_effect then
    let loc = e_locate_effect writes e in
    Loc.error ?loc (IllegalUpdate (v,r))) el;
  raise (IllegalUpdate (v,r))

(* localize a reset effect *)
let localize_reset_stale v r el =
  let resets eff =
    if Sreg.mem r eff.eff_resets then
      ity_r_stale (Sreg.singleton r) eff.eff_covers v.pv_ity
    else false in
  List.iter (fun e -> if resets e.e_effect then
    let loc = e_locate_effect resets e in
    Loc.error ?loc (StaleVariable (v,r))) el;
  raise (StaleVariable (v,r))

(* localize a divergence *)
let localize_divergence el =
  let diverges eff = eff.eff_oneway in
  List.iter (fun e -> if diverges e.e_effect then
    let loc = e_locate_effect diverges e in
    Loc.error ?loc GhostDivergence) el;
  raise GhostDivergence

let try_effect el fn x y = try fn x y with
  | BadGhostWrite (v,r) -> localize_ghost_write v r el
  | IllegalUpdate (v,r) -> localize_immut_write v r el
  | StaleVariable (v,r) -> localize_reset_stale v r el
  | GhostDivergence     -> localize_divergence el

(* smart constructors *)

let mk_expr node ity mask eff = {
  e_node   = node;
  e_ity    = ity;
  e_mask   = if eff.eff_ghost then MaskGhost else mask;
  e_effect = eff;
  e_label  = Slab.empty;
  e_loc    = None;
}

let mk_cexp node cty = {
  c_node   = node;
  c_cty    = cty;
}

let e_var ({pv_ity = ity; pv_ghost = ghost} as v) =
  let eff = eff_ghostify ghost (eff_read_single v) in
  mk_expr (Evar v) ity MaskVisible eff

let e_const c =
  let ity = match c with
    | Number.ConstInt  _ -> ity_int
    | Number.ConstReal _ -> ity_real in
  mk_expr (Econst c) ity MaskVisible eff_empty

let e_nat_const n =
  e_const (Number.ConstInt (Number.int_const_dec (string_of_int n)))

let e_ghostify gh ({e_effect = eff} as e) =
  if not gh then e else
  let eff = try_effect [e] eff_ghostify gh eff in
  mk_expr (Eghost e) e.e_ity e.e_mask eff

let c_cty_ghostify gh ({c_cty = cty} as c) =
  if not gh || cty.cty_effect.eff_ghost then cty else
  let el = match c.c_node with Cfun e -> [e] | _ -> [] in
  try_effect el Ity.cty_ghostify gh cty

(* purify expressions *)

let rs_true  = rs_of_ls fs_bool_true
let rs_false = rs_of_ls fs_bool_false

let is_e_true e = match e.e_node with
  | Eexec {c_node = Capp (s,[])} -> rs_equal s rs_true
  | _ -> false

let is_e_false e = match e.e_node with
  | Eexec {c_node = Capp (s,[])} -> rs_equal s rs_false
  | _ -> false

let t_void = t_tuple []

let is_rlpv s = match s.rs_logic with
  | RLpv _ -> true | _ -> false

let copy_labels e t =
  if e.e_loc = None && Slab.is_empty e.e_label then t else
  let loc = if t.t_loc = None then e.e_loc else t.t_loc in
  t_label ?loc (Slab.union e.e_label t.t_label) t

let rec raw_of_expr e = copy_labels e (match e.e_node with
  | _ when ity_equal e.e_ity ity_unit -> t_void
    (* we do not check e.e_effect here, since we check the
        effects later for the overall expression. The only
        effect-hiding construction, Etry, is forbidden. *)
  | Eassign _ | Ewhile _ | Efor _ | Eassert _ -> assert false
  | Evar v -> t_var v.pv_vs
  | Econst n -> t_const n
  | Epure t -> t
  | Eghost e -> raw_of_expr e
  | Eexec {c_cty = {cty_args = al; cty_post = q::_}} ->
      let v, f = open_post q in
      let t = match f.t_node with
        | Tapp (ps, [{t_node = Tvar u}; t])
          when ls_equal ps ps_equ && vs_equal v u && t_v_occurs v t = 0 -> t
        | Tbinop (Tiff, {t_node =
            Tapp (ps,[{t_node = Tvar u}; {t_node = Tapp (fs,[])}])},f)
          when ls_equal ps ps_equ && vs_equal v u &&
               ls_equal fs fs_bool_true && t_v_occurs v f = 0 -> f
        | _ -> raise Exit in
      begin match t.t_node, al with
        | Tapp (s, tl), _::_ ->
            let rec down el vl = match el, vl with
              | {t_node = Tvar u}::el, {pv_vs = v}::vl when vs_equal u v ->
                  down el vl
              | el, [] ->
                  let tyl = List.map (fun v -> v.pv_vs.vs_ty) al in
                  t_app_partial s (List.rev el) tyl t.t_ty
              | _ ->
                  t_lambda (List.map (fun v -> v.pv_vs) al) [] t in
            down (List.rev tl) (List.rev al)
        | _, _::_ ->
            t_lambda (List.map (fun v -> v.pv_vs) al) [] t
        | _, [] -> t end
  | Eexec _ -> raise Exit
  | Elet (LDvar (v,_d),e) when ity_equal v.pv_ity ity_unit ->
      t_subst_single v.pv_vs t_void (raw_of_expr e)
  | Elet (LDvar (v,d),e) ->
      t_let_close_simp v.pv_vs (pure_of_expr false d) (raw_of_expr e)
  | Elet (LDsym (s,_),e) ->
      (* TODO/FIXME: should we create a lambda-term for RLpv here instead
          of failing? Why would anyone want to define a local let-function,
          if it already has a pure logical meaning? *)
      if is_rlpv s then raise Exit;
      raw_of_expr e
  | Elet (LDrec rdl,e) ->
      if List.exists (fun rd -> is_rlpv rd.rec_sym) rdl then raise Exit;
      raw_of_expr e
  | Eif (e0,e1,e2) when is_e_false e1 && is_e_true e2 ->
      t_not (pure_of_expr true e0)
  | Eif (e0,e1,e2) when is_e_false e2 ->
      t_and (pure_of_expr true e0) (pure_of_expr true e1)
  | Eif (e0,e1,e2) when is_e_true e1 ->
      t_or (pure_of_expr true e0) (pure_of_expr true e2)
  | Eif (e0,e1,e2) ->
      let prop = ity_equal e.e_ity ity_bool in
      t_if (pure_of_expr true e0) (pure_of_expr prop e1) (pure_of_expr prop e2)
  | Ecase (d,bl) ->
      let prop = ity_equal e.e_ity ity_bool in
      let conv (p,e) = t_close_branch p.pp_pat (pure_of_expr prop e) in
      t_case (pure_of_expr false d) (List.map conv bl)
  | Etry _ | Eraise _ | Eabsurd -> raise Exit)

and pure_of_expr prop e =
  let loca f = t_label ?loc:e.e_loc Slab.empty f in
  let t = raw_of_expr e in
  match t.t_ty with
  | None when not prop -> loca (t_if_simp t t_bool_true t_bool_false)
  | Some _ when prop -> loca (t_equ_simp t t_bool_true)
  | _ -> t

let term_of_expr ~prop e =
  if not (eff_pure e.e_effect) then None else
  try Some (pure_of_expr prop e) with Exit -> None

let post_of_term res t =
  let loca f = t_label ?loc:t.t_loc Slab.empty f in
  let f_of_t t = loca (t_equ_simp t t_bool_true) in
  match res.t_ty, t.t_ty with
  | Some _, Some _ -> loca (t_equ_simp res t)
  | None,   None   -> loca (t_iff_simp res t)
  | Some _, None   -> loca (t_iff_simp (f_of_t res) t)
  | None,   Some _ -> loca (t_iff_simp res (f_of_t t))

let rec post_of_expr res e = match e.e_node with
  | _ when ity_equal e.e_ity ity_unit -> t_true
  | Eassign _ | Ewhile _ | Efor _ | Eassert _ -> assert false
  | Eabsurd -> copy_labels e t_false
  | Elet (LDvar (v,_d),e) when ity_equal v.pv_ity ity_unit ->
      copy_labels e (t_subst_single v.pv_vs t_void (post_of_expr res e))
  | Elet (LDvar (v,d),e) ->
      copy_labels e (t_let_close_simp v.pv_vs
        (pure_of_expr false d) (post_of_expr res e))
  | Elet (LDsym (s,_),e) ->
      if is_rlpv s then raise Exit;
      copy_labels e (post_of_expr res e)
  | Elet (LDrec rdl,e) ->
      if List.exists (fun rd -> is_rlpv rd.rec_sym) rdl then raise Exit;
      copy_labels e (post_of_expr res e)
  | Eif (_,e1,e2) when is_e_true e1 || is_e_false e2 ||
                      (is_e_false e1 && is_e_true e2) ->
      post_of_term res (raw_of_expr e)
  | Eif (e0,e1,e2) ->
      t_if (pure_of_expr true e0) (post_of_expr res e1) (post_of_expr res e2)
  | Ecase (d,bl) ->
      let conv (p,e) = t_close_branch p.pp_pat (post_of_expr res e) in
      t_case (pure_of_expr false d) (List.map conv bl)
  | Etry _ | Eraise _ -> raise Exit
  | _ -> post_of_term res (raw_of_expr e)

let local_post_of_expr e =
  if ity_equal e.e_ity ity_unit || not (eff_pure e.e_effect) then [] else
  let res = create_vsymbol (id_fresh "result") (ty_of_ity e.e_ity) in
  try [create_post res (post_of_expr (t_var res) e)] with Exit -> []

let post_of_expr res e =
  ty_equal_check (ty_of_ity e.e_ity)
    (match res.t_ty with Some ty -> ty | None -> ty_bool);
  if ity_equal e.e_ity ity_unit || not (eff_pure e.e_effect) then None
  else try
    (* we avoid capturing the free variables of res *)
    let clone v _ = create_vsymbol (id_clone v.vs_name) v.vs_ty in
    let sbs = Mvs.mapi clone (t_vars res) in
    let res = t_subst (Mvs.map t_var sbs) res in
    let q = post_of_expr res e in
    let inverse o n m = Mvs.add n (t_var o) m in
    Some (t_subst (Mvs.fold inverse sbs Mvs.empty) q)
  with Exit -> None

(* let-definitions *)

let let_var id ?(ghost=false) e =
  let ghost = ghost || mask_ghost e.e_mask in
  let v = create_pvsymbol id ~ghost e.e_ity in
  LDvar (v,e), v

let let_sym id ?(ghost=false) ?(kind=RKnone) c =
  let cty = c_cty_ghostify ghost c in
  (* we do not compute implicit post-conditions for let-functions,
     as this would be equivalent to auto-inlining of the generated
     logical function definition. FIXME: Should we make exception
     for local let-functions? We do have a mapping definition in
     the antecedents of WP, but provers must perform beta-reduction
     to apply it: auto-inlining might be really helpful here. *)
  let cty = match c with
    | {c_node = Cfun e; c_cty = {cty_post = []}}
      when (kind = RKnone (*|| kind = RKlocal*)) ->
        cty_add_post cty (local_post_of_expr e)
    | _ -> cty in
  let s = create_rsymbol id ~kind cty in
  LDsym (s,c), s

let e_let ld e =
  let bind_pv v eff = eff_bind_single v eff in
  let bind_rs s eff = match s.rs_logic with
    | RLls _ -> invalid_arg "Expr.e_let"
    | RLpv v -> bind_pv v eff | _ -> eff in
  let bind_rd d eff = bind_rs d.rec_sym eff in
  let eff = match ld with
    | LDvar (v,d) ->
        try_effect [d;e] eff_union_seq d.e_effect (bind_pv v e.e_effect)
    | LDsym (s,c) ->
        try_effect [e] eff_read_pre (cty_reads c.c_cty) (bind_rs s e.e_effect)
    | LDrec dl ->
        let e_effect = List.fold_right bind_rd dl e.e_effect in
        (* We do not use the effect of rec_fun, because it does not
           necessarily depend on the external variables in rec_varl.
           We do not use the effect of rec_sym, because it contains
           the RLpv variable when we define a local let-function. *)
        let add s d = Spv.union s (cty_reads d.rec_rsym.rs_cty) in
        let rd = List.fold_left add Spv.empty dl in
        try_effect [e] eff_read_pre rd e_effect in
  mk_expr (Elet (ld,e)) e.e_ity e.e_mask eff

(* callable expressions *)

let e_exec ({c_cty = cty} as c) = match cty.cty_args with
  | _::_ as al ->
      (* unlike for RLpv or RLls, we do not purify the signature,
         so the regions are now frozen and we have to forbid all
         effects, including allocation *)
      check_effects cty; check_state cty;
      if not (Sreg.is_empty cty.cty_effect.eff_resets) then Loc.errorm
        "This function has side effects, it cannot be used as pure";
      let func a ity = ity_func a.pv_ity ity in
      let ity = List.fold_right func al cty.cty_result in
      let ghost = List.exists (fun a -> a.pv_ghost) al in
      let eff = eff_ghostify ghost cty.cty_effect in
      mk_expr (Eexec c) ity MaskVisible eff
  | [] ->
      mk_expr (Eexec c) cty.cty_result cty.cty_mask cty.cty_effect

let c_any c = mk_cexp Cany c

let c_fun ?(mask=MaskVisible) args p q xq old ({e_effect = eff} as e) =
  let mask = mask_union mask e.e_mask in
  (* reset variables are forbidden in post-conditions *)
  let c = try create_cty ~mask args p q xq old eff e.e_ity with
    | BadGhostWrite (v,r) -> localize_ghost_write v r [e]
    | IllegalUpdate (v,r) -> localize_immut_write v r [e]
    | StaleVariable (v,r) -> localize_reset_stale v r [e] in
  mk_cexp (Cfun e) c

let c_app s vl ityl ity =
  let cty = cty_apply s.rs_cty vl ityl ity in
  let cty = match s.rs_logic with
    | RLls ls when ityl = [] && is_fs_tuple ls -> cty_tuple vl
    | _ -> cty in
  mk_cexp (Capp (s,vl)) cty

let c_pur s vl ityl ity =
  if not (ity_pure ity) then Loc.errorm "This expression must have pure type";
  let v_args = List.map (create_pvsymbol ~ghost:false (id_fresh "u")) ityl in
  let t_args = List.map (fun v -> t_var v.pv_vs) (vl @ v_args) in
  let res = Opt.map (fun _ -> ty_of_ity ity) s.ls_value in
  let q = make_post (t_app s t_args res) in
  let eff = eff_ghostify true eff_empty in
  let cty = create_cty v_args [] [q] Mexn.empty Mpv.empty eff ity in
  mk_cexp (Cpur (s,vl)) cty

let proxy_label = create_label "whyml_proxy_symbol"
let proxy_labels = Slab.singleton proxy_label

let mk_proxy e hd = match e.e_node with
  | Evar v when Slab.is_empty e.e_label -> hd, v
  | _ ->
      let id = id_fresh ?loc:e.e_loc ~label:proxy_labels "o" in
      let ld, v = let_var id e in ld::hd, v

let add_proxy e (hd,vl) = let hd, v = mk_proxy e hd in hd, v::vl

let let_head hd e = List.fold_left (fun e ld -> e_let ld e) e hd

let e_app s el ityl ity =
  let hd, vl = List.fold_right add_proxy el ([],[]) in
  let_head hd (e_exec (c_app s vl ityl ity))

let e_pur s el ityl ity =
  let hd, vl = List.fold_right add_proxy el ([],[]) in
  let_head hd (e_exec (c_pur s vl ityl ity))

(* assignment *)

let e_assign_raw al =
  let conv (r,f,v) = r, mfield_of_rs f, v in
  mk_expr (Eassign al) ity_unit MaskVisible (eff_assign (List.map conv al))

let e_assign al =
  let hr, hv, al = List.fold_right (fun (r,f,v) (hr,hv,al) ->
    let hv, v = mk_proxy v hv in
    let hr, r = mk_proxy r hr in
    hr, hv, (r,f,v)::al) al ([],[],[]) in
  (* first pants, THEN your shoes *)
  let_head hv (let_head hr (e_assign_raw al))

(* built-in symbols *)

let e_true  = e_app rs_true  [] [] ity_bool
let e_false = e_app rs_false [] [] ity_bool

let rs_tuple = Hint.memo 17 (fun n ->
  ignore (its_tuple n); rs_of_ls (fs_tuple n))

let is_rs_tuple rs = rs_equal rs (rs_tuple (List.length rs.rs_cty.cty_args))

let e_tuple el =
  let ity = ity_tuple (List.map (fun e -> e.e_ity) el) in
  e_app (rs_tuple (List.length el)) el [] ity

let rs_void = rs_tuple 0

let e_void = e_app rs_void [] [] ity_unit

let is_e_void e = match e.e_node with
  | Eexec {c_node = Capp (s,[])} -> rs_equal s rs_void
  | _ -> false

let rs_func_app = rs_of_ls fs_func_app

let ld_func_app =
  let v_args = rs_func_app.rs_cty.cty_args in
  let ity = rs_func_app.rs_cty.cty_result in
  let c = create_cty v_args [] [] Mexn.empty Mpv.empty eff_empty ity in
  LDsym (rs_func_app, c_any c)

let e_func_app fn e =
  let c = rs_func_app.rs_cty in
  let mtch isb a e = ity_match isb a.pv_ity e.e_ity in
  let isb = List.fold_left2 mtch c.cty_freeze c.cty_args [fn;e] in
  e_app rs_func_app [fn;e] [] (ity_full_inst isb c.cty_result)

let e_func_app_l fn el = List.fold_left e_func_app fn el

(* boolean constructors *)

let e_if e0 e1 e2 =
  ity_equal_check e0.e_ity ity_bool;
  ity_equal_check e1.e_ity e2.e_ity;
  let eff = try_effect [e1;e2] eff_union_par e1.e_effect e2.e_effect in
  let eff = try_effect [e0;e1;e2] eff_union_seq e0.e_effect eff in
  let ghost = mask_ghost e0.e_mask && e1.e_node <> Eabsurd &&
                                      e2.e_node <> Eabsurd in
  let eff = try_effect [e0;e1;e2] eff_ghostify ghost eff in
  mk_expr (Eif (e0,e1,e2)) e1.e_ity (mask_union e1.e_mask e2.e_mask) eff

let e_and e1 e2 = e_if e1 e2 e_false
let e_or e1 e2 = e_if e1 e_true e2
let e_not e = e_if e e_false e_true

(* loops *)

let e_for_raw v ((f,_,t) as bounds) inv e =
  ity_equal_check v.pv_ity ity_int;
  ity_equal_check f.pv_ity ity_int;
  ity_equal_check t.pv_ity ity_int;
  ity_equal_check e.e_ity ity_unit;
  let vars = List.fold_left t_freepvs Spv.empty inv in
  let ghost = v.pv_ghost || f.pv_ghost || t.pv_ghost in
  let eff = try_effect [e] eff_read_pre vars e.e_effect in
  let eff = try_effect [e] eff_ghostify ghost eff in
  ignore (try_effect [e] eff_union_seq eff eff);
  let eff = eff_bind_single v eff in
  let eff = eff_read_single_pre t eff in
  let eff = eff_read_single_pre f eff in
  mk_expr (Efor (v,bounds,inv,e)) e.e_ity MaskVisible eff

let e_for v f dir t inv e =
  let hd, t = mk_proxy t [] in
  let hd, f = mk_proxy f hd in
  let_head hd (e_for_raw v (f,dir,t) inv e)

let e_while d inv vl e =
  ity_equal_check d.e_ity ity_bool;
  ity_equal_check e.e_ity ity_unit;
  let add_v s (t,_) = t_freepvs s t in
  let vars = List.fold_left add_v Spv.empty vl in
  let vars = List.fold_left t_freepvs vars inv in
  let eff = try_effect [e] eff_read_pre vars e.e_effect in
  let eff = try_effect [d;e] eff_union_seq d.e_effect eff in
  let eff = try_effect [d;e] eff_ghostify (mask_ghost d.e_mask) eff in
  let eff = if vl = [] then eff_diverge eff else eff in
  ignore (try_effect [d;e] eff_union_seq eff eff);
  mk_expr (Ewhile (d,inv,vl,e)) e.e_ity MaskVisible eff

(* match-with, try-with, raise *)

let e_case e bl =
  let ity = match bl with
    | (_,d)::_ -> d.e_ity
    | [] -> invalid_arg "Expr.e_case" in
  List.iter (fun (p,d) ->
    if mask_spill e.e_mask p.pp_mask then
      Loc.errorm "Non-ghost pattern in a ghost position";
    ity_equal_check d.e_ity ity;
    ity_equal_check e.e_ity p.pp_ity) bl;
  (* absurd branches can be eliminated, any pattern with
     a refutable ghost subpattern makes the whole match
     ghost, unless it is the last branch, in which case
     the pattern is actually irrefutable *)
  let rec scan last = function
    | (_,{e_node = Eabsurd})::bl -> scan last bl
    | ({pp_fail = PGnone},_)::bl -> last || scan last bl
    | ({pp_fail = PGlast},_)::bl -> last || scan true bl
    | ({pp_fail = PGfail},_)::_  -> true
    | [] -> false in
  let ghost = scan false bl and dl = List.map snd bl in
  let add_mask mask d = mask_union mask d.e_mask in
  let mask = List.fold_left add_mask MaskVisible dl in
  let eff = List.fold_left (fun eff (p,d) ->
    let pvs = pvs_of_vss Spv.empty p.pp_pat.pat_vars in
    let dff = eff_bind pvs d.e_effect in
    try_effect dl eff_union_par eff dff) eff_empty bl in
  let eff = try_effect (e::dl) eff_union_seq e.e_effect eff in
  let eff = try_effect (e::dl) eff_ghostify ghost eff in
  mk_expr (Ecase (e,bl)) ity mask eff

let e_try e xl =
  List.iter (fun (xs,v,d) ->
    ity_equal_check v.pv_ity xs.xs_ity;
    ity_equal_check d.e_ity e.e_ity) xl;
  let ghost = e.e_effect.eff_ghost in
  let eeff = List.fold_left (fun eff (xs,_,_) ->
    eff_catch eff xs) e.e_effect xl in
  let dl = List.map (fun (_,_,d) -> d) xl in
  let add_mask mask d = mask_union mask d.e_mask in
  let mask = List.fold_left add_mask e.e_mask dl in
  let xeff = List.fold_left (fun eff (_,v,d) ->
    let dff = eff_bind_single v d.e_effect in
    try_effect dl eff_union_par eff dff) eff_empty xl in
  let eff = try_effect (e::dl) eff_union_seq eeff xeff in
  let eff = try_effect (e::dl) eff_ghostify ghost eff in
  mk_expr (Etry (e,xl)) e.e_ity mask eff

let e_raise xs e ity =
  ity_equal_check e.e_ity xs.xs_ity;
  let ghost = mask_spill e.e_mask xs.xs_mask in
  let eff = eff_ghostify ghost (eff_raise eff_empty xs) in
  let eff = try_effect [e] eff_union_seq e.e_effect eff in
  mk_expr (Eraise (xs,e)) ity MaskVisible eff

(* snapshots, assertions, "any" *)

let e_pure t =
  let ity = Opt.fold (Util.const ity_of_ty_pure) ity_bool t.t_ty in
  let eff = eff_ghostify true (eff_read (t_freepvs Spv.empty t)) in
  mk_expr (Epure t) ity MaskGhost eff

let e_assert ak f =
  let eff = eff_read (t_freepvs Spv.empty f) in
  mk_expr (Eassert (ak, t_prop f)) ity_unit MaskVisible eff

let e_absurd ity = mk_expr Eabsurd ity MaskVisible eff_empty

(* recursive definitions *)

let cty_add_variant d varl = let add s (t,_) = t_freepvs s t in
  cty_read_pre (List.fold_left add Spv.empty varl) d.c_cty

let rec e_rs_subst sm e = e_label_copy e (match e.e_node with
  | Evar _ | Econst _ | Eassign _ | Eassert _ | Epure _ | Eabsurd -> e
  | Eghost e -> e_ghostify true (e_rs_subst sm e)
  | Eexec c -> e_exec (c_rs_subst sm c)
  | Elet (LDvar (v,d),e) ->
      let d = e_rs_subst sm d in
      ity_equal_check d.e_ity v.pv_ity;
      if mask_ghost d.e_mask && not v.pv_ghost then Loc.errorm
        "Expr.let_rec: ghost status mismatch";
      e_let (LDvar (v,d)) (e_rs_subst sm e)
  | Elet (LDsym (s,d),e) ->
      let d = c_rs_subst sm d in
      if c_ghost d && not (rs_ghost s) then Loc.errorm
        "Expr.let_rec: ghost status mismatch";
      let ns = rs_dup s d.c_cty in
      e_let (LDsym (ns,d)) (e_rs_subst (Mrs.add s ns sm) e)
  | Elet (LDrec fdl,e) ->
      let ndl = List.map (fun fd ->
        fd.rec_rsym, c_rs_subst sm fd.rec_fun) fdl in
      let merge {rec_sym = s; rec_varl = varl} (rs,d) =
        { rec_sym = rs_dup s (cty_add_variant d varl);
          rec_rsym = rs; rec_fun = d; rec_varl = varl } in
      let nfdl = List.map2 merge fdl (rec_fixp ndl) in
      let add m o n = Mrs.add o.rec_sym n.rec_sym m in
      let sm = List.fold_left2 add sm fdl nfdl in
      e_let (LDrec nfdl) (e_rs_subst sm e)
  | Eif (c,d,e) -> e_if (e_rs_subst sm c) (e_rs_subst sm d) (e_rs_subst sm e)
  | Efor (v,b,inv,e) -> e_for_raw v b inv (e_rs_subst sm e)
  | Ewhile (d,inv,vl,e) -> e_while (e_rs_subst sm d) inv vl (e_rs_subst sm e)
  | Eraise (xs,d) -> e_raise xs (e_rs_subst sm d) e.e_ity
  | Ecase (d,bl) -> e_case (e_rs_subst sm d)
      (List.map (fun (pp,e) -> pp, e_rs_subst sm e) bl)
  | Etry (d,xl) -> e_try (e_rs_subst sm d)
      (List.map (fun (xs,v,e) -> xs, v, e_rs_subst sm e) xl))

and c_rs_subst sm ({c_node = n; c_cty = c} as d) = match n with
  | Cany | Cpur _ -> d
  | Capp (s,vl) ->
      let al = List.map (fun v -> v.pv_ity) c.cty_args in
      c_app (Mrs.find_def s s sm) vl al c.cty_result
  | Cfun e ->
      c_fun ~mask:c.cty_mask c.cty_args c.cty_pre
        c.cty_post c.cty_xpost c.cty_oldies (e_rs_subst sm e)

and rec_fixp dl =
  let update sm (s,d) =
    if cty_ghost d.c_cty && not (rs_ghost s) then Loc.errorm
      "Expr.let_rec: ghost status mismatch";
    let c = c_cty_ghostify (rs_ghost s) d in
    let c = if List.length c.cty_pre < List.length s.rs_cty.cty_pre
            then cty_add_pre [List.hd s.rs_cty.cty_pre] c else c in
    if eff_equal c.cty_effect s.rs_cty.cty_effect &&
       mask_equal c.cty_mask s.rs_cty.cty_mask then sm, (s,d)
    else let n = rs_dup s c in Mrs.add s n sm, (n,d) in
  let sm, dl = Lists.map_fold_left update Mrs.empty dl in
  if Mrs.is_empty sm then dl else
  rec_fixp (List.map (fun (s,d) -> s, c_rs_subst sm d) dl)

let let_rec fdl =
  (* check that the variant relations are well-typed *)
  List.iter (fun (_,_,vl,_) -> List.iter (function
    | t, Some rel -> ignore (ps_app rel [t;t])
    | t, None     -> ignore (t_type t)) vl) fdl;
  (* check that the all variants use the same order *)
  let varl1 = match fdl with
    | (_,_,vl,_)::_ -> vl
    | [] -> invalid_arg "Expr.let_rec" in
  let check_variant (_,_,vl,_) = match vl, varl1 with
    | [], []
    | (_,None)::_, (_,None)::_ -> ()
    | (t1, Some r1)::_, (t2, Some r2)::_
      when oty_equal t1.t_ty t2.t_ty && ls_equal r1 r2 -> ()
    | _, _ -> Loc.errorm
        "All functions in a recursive definition must use the same \
        well-founded order for the first component of the variant" in
  List.iter check_variant (List.tl fdl);
  (* if we have a top-level total let-function definition and
     no variants are supplied, then we expect the definition
     to be terminating with respect to Decl.check_termination *)
  let impure (_,d,_,k) =
    (k <> RKfunc && k <> RKpred) || d.c_cty.cty_pre <> [] in
  let start_eff = if varl1 = [] && List.exists impure fdl then
    eff_diverge eff_empty else eff_empty in
  (* create the first substitution *)
  let update sm (s,({c_cty = c} as d),varl,_) =
    (* check that the type signatures are consistent *)
    let same u v =
      u.pv_ghost = v.pv_ghost && ity_equal u.pv_ity v.pv_ity in
    if (match d.c_node with Cfun _ -> false | _ -> true) ||
       not (Lists.equal same s.rs_cty.cty_args c.cty_args) ||
       not (ity_equal s.rs_cty.cty_result c.cty_result) ||
       mask_spill c.cty_mask s.rs_cty.cty_mask ||
       (c_ghost d && not (rs_ghost s)) ||
       s.rs_logic <> RLnone ||
       c.cty_args = []
    then invalid_arg "Expr.let_rec";
    (* prepare the extra "decrease" precondition *)
    let pre = match varl with
      | [] -> c.cty_pre
      | _::_ ->
          let tl = List.map fst varl in
          let id = id_fresh ("DECR " ^ s.rs_name.id_string) in
          let ps = create_psymbol id (List.map t_type tl) in
          ps_app ps tl :: c.cty_pre in
    (* create the clean rsymbol *)
    let id = id_clone s.rs_name in
    let c = create_cty ~mask:c.cty_mask c.cty_args pre
      c.cty_post c.cty_xpost c.cty_oldies start_eff c.cty_result in
    let ns = create_rsymbol id ~ghost:(rs_ghost s) ~kind:RKnone c in
    let sm = Mrs.add_new (Invalid_argument "Expr.let_rec") s ns sm in
    sm, (ns, d) in
  let sm, dl = Lists.map_fold_left update Mrs.empty fdl in
  (* produce the recursive definition *)
  let conv (s,d) = s, c_rs_subst sm d in
  let merge (_,_,varl,kind) (rs,d) =
    let id = id_clone rs.rs_name in
    let c = cty_add_variant d varl in
    let s = create_rsymbol id ~kind ~ghost:(rs_ghost rs) c in
    { rec_sym = s; rec_rsym = rs; rec_fun = d; rec_varl = varl } in
  let rdl = List.map2 merge fdl (rec_fixp (List.map conv dl)) in
  LDrec rdl, rdl

let ls_decr_of_rec_defn = function
  | { rec_rsym = {rs_cty = {cty_pre = {t_node = Tapp (ls,_)}::_}};
      rec_varl = _::_ } -> Some ls
  | _ -> None

(* pretty-pringting *)

open Format
open Pretty

let sprinter = create_ident_printer []
  ~sanitizer:(sanitizer char_to_alpha char_to_alnumus)

let id_of_rs s = match s.rs_logic with
  | RLnone | RLlemma -> s.rs_name
  | RLpv v -> v.pv_vs.vs_name
  | RLls s -> s.ls_name

let forget_rs s = match s.rs_logic with
  | RLnone | RLlemma -> forget_id sprinter s.rs_name
  | RLpv v -> forget_pv v
  | RLls _ -> () (* we don't forget top-level symbols *)

let forget_let_defn = function
  | LDvar (v,_) -> forget_pv v
  | LDsym (s,_) -> forget_rs s
  | LDrec rdl -> List.iter (fun fd -> forget_rs fd.rec_sym) rdl

let extract_op s =
  let s = s.id_string in
  let len = String.length s in
  if len < 7 then None else
  let inf = String.sub s 0 6 in
  if inf = "infix "  then Some (String.sub s 6 (len - 6)) else
  let prf = String.sub s 0 7 in
  if prf = "prefix " then Some (String.sub s 7 (len - 7)) else
  None

let tight_op s = let c = String.sub s 0 1 in c = "!" || c = "?"

let print_rs fmt ({rs_name = {id_string = nm}} as s) =
  if nm = "mixfix []" then pp_print_string fmt "([])" else
  if nm = "mixfix []<-" then pp_print_string fmt "([]<-)" else
  if nm = "mixfix [<-]" then pp_print_string fmt "([<-])" else
  if nm = "mixfix [_..]" then pp_print_string fmt "([_..])" else
  if nm = "mixfix [.._]" then pp_print_string fmt "([.._])" else
  if nm = "mixfix [_.._]" then pp_print_string fmt "([_.._])" else
  match extract_op s.rs_name, s.rs_logic with
  | Some s, _ ->
      let s = Str.replace_first (Str.regexp "^\\*.") " \\0" s in
      let s = Str.replace_first (Str.regexp ".\\*$") "\\0 " s in
      fprintf fmt "(%s)" s
  | _, RLnone | _, RLlemma ->
      pp_print_string fmt (id_unique sprinter s.rs_name)
  | _, RLpv v -> print_pv fmt v
  | _, RLls s -> print_ls fmt s

let print_rs_head fmt s = fprintf fmt "%s%s%a%a"
  (if s.rs_cty.cty_effect.eff_ghost then "ghost " else "")
  (match s.rs_logic with
    | RLnone -> ""
    | RLpv _ -> "function "
    | RLls {ls_value = None} -> "predicate "
    | RLls _ -> "function "
    | RLlemma -> "lemma ")
  print_rs s print_id_labels (id_of_rs s)

let print_invariant fmt fl =
  let print_inv fmt f = fprintf fmt "@\ninvariant@ { %a }" print_term f in
  Pp.print_list Pp.nothing print_inv fmt fl

let print_variant fmt varl =
  let print_rel fmt = function
    | Some s -> fprintf fmt "@ with %a" print_ls s
    | None -> () in
  let print_var fmt (t,s) =
    fprintf fmt " %a%a" Pretty.print_term t print_rel s in
  if varl <> [] then fprintf fmt "@\nvariant@   {%a }@ "
    (Pp.print_list Pp.comma print_var) varl

(* expressions *)

let protect_on x s = if x then "(" ^^ s ^^ ")" else s

let debug_print_labels = Debug.register_info_flag "print_labels"
  ~desc:"Print@ labels@ of@ identifiers@ and@ expressions."

let debug_print_locs = Debug.register_info_flag "print_locs"
  ~desc:"Print@ locations@ of@ identifiers@ and@ expressions."

let ambig_cty c =
  let freeze_pv v s = ity_freeze s v.pv_ity in
  let sarg = List.fold_right freeze_pv c.cty_args isb_empty in
  let sarg = Spv.fold freeze_pv c.cty_effect.eff_reads sarg in
  let sres = ity_freeze isb_empty c.cty_result in
  not (Mtv.set_submap sres.isb_var sarg.isb_var) ||
  not (Mtv.set_submap sres.isb_pur
       (Mtv.set_union sarg.isb_var sarg.isb_pur))

let ambig_ls s =
  let sarg = List.fold_left ty_freevars Stv.empty s.ls_args in
  let sres = Opt.fold ty_freevars Stv.empty s.ls_value in
  not (Stv.subset sres sarg)

let ht_rs = Hrs.create 7 (* rec_rsym -> rec_sym *)

let print_apply pri print s id fmt vl = match extract_op id, vl with
  | _, [] ->
      print fmt s
  | Some o, [t1] when tight_op o ->
      fprintf fmt (protect_on (pri > 7) "%s%a") o print_pv t1
  | Some o, [t1] when String.get id.id_string 0 = 'p' ->
      fprintf fmt (protect_on (pri > 4) "%s %a") o print_pv t1
  | Some o, [t1;t2] ->
      fprintf fmt (protect_on (pri > 4) "@[<hov 1>%a %s@ %a@]")
        print_pv t1 o print_pv t2
  | _, [t1;t2] when id.id_string = "mixfix []" ->
      fprintf fmt (protect_on (pri > 6) "%a[%a]") print_pv t1 print_pv t2
  | _, [t1;t2;t3] when id.id_string = "mixfix [<-]" ->
      fprintf fmt (protect_on (pri > 6) "%a[%a <- %a]")
        print_pv t1 print_pv t2 print_pv t3
  | _, [t1;t2;t3] when id.id_string = "mixfix []<-" ->
      fprintf fmt (protect_on (pri > 0) "%a[%a] <- %a")
        print_pv t1 print_pv t2 print_pv t3
  | _, [t1;t2] when id.id_string = "mixfix [_..]" ->
      fprintf fmt (protect_on (pri > 6) "%a[%a..]") print_pv t1 print_pv t2
  | _, [t1;t2] when id.id_string = "mixfix [.._]" ->
      fprintf fmt (protect_on (pri > 6) "%a[..%a]") print_pv t1 print_pv t2
  | _, [t1;t2;t3] when id.id_string = "mixfix [_.._]" ->
      fprintf fmt (protect_on (pri > 6) "%a[%a..%a]")
        print_pv t1 print_pv t2 print_pv t3
  | _, tl ->
      fprintf fmt (protect_on (pri > 5) "@[<hov 1>%a@ %a@]")
        print s (Pp.print_list Pp.space print_pv) tl

let print_capp pri s fmt vl = print_apply pri print_rs s s.rs_name fmt vl

let print_cpur pri s fmt vl = print_apply pri print_ls s s.ls_name fmt vl

let rec print_expr fmt e = print_lexpr 0 fmt e

and print_lexpr pri fmt e =
  let print_elab pri fmt e =
    if Debug.test_flag debug_print_labels && not (Slab.is_empty e.e_label)
    then fprintf fmt (protect_on (pri > 0) "@[<hov 0>%a@ %a@]")
      (Pp.print_iter1 Slab.iter Pp.space print_label) e.e_label
      (print_enode 0) e
    else print_enode pri fmt e in
  let print_eloc pri fmt e =
    if Debug.test_flag debug_print_locs && e.e_loc <> None
    then fprintf fmt (protect_on (pri > 0) "@[<hov 0>%a@ %a@]")
      (Pp.print_option print_loc) e.e_loc (print_elab 0) e
    else print_elab pri fmt e in
  print_eloc pri fmt e

and print_cexp exec pri fmt {c_node = n; c_cty = c} = match n with
  | Cany when exec && c.cty_args = [] ->
      fprintf fmt "@[<hov 2>any %a%a@]" print_ity c.cty_result
        (print_spec [] c.cty_pre c.cty_post c.cty_xpost
          c.cty_oldies c.cty_effect) None
  | Cany ->
      fprintf fmt "@[<hov 2>any%a@]" print_cty c;
      forget_cty c
  | Cfun e when exec && c.cty_args = [] ->
      fprintf fmt "@[<hov 2>abstract%a@\n%a@]@\nend"
        (print_spec [] c.cty_pre c.cty_post c.cty_xpost
          c.cty_oldies eff_empty) None print_expr e
  | Cfun e ->
      fprintf fmt "@[<hov 2>fun%a ->@\n%a@]"
        (print_spec c.cty_args c.cty_pre c.cty_post c.cty_xpost
          c.cty_oldies eff_empty) None print_expr e;
      forget_cty c
  | Capp (s,[]) when rs_equal s rs_true ->
      pp_print_string fmt "true"
  | Capp (s,[]) when rs_equal s rs_false ->
      pp_print_string fmt "false"
  | Capp (s,vl) when is_rs_tuple s ->
      fprintf fmt "(%a)" (Pp.print_list Pp.comma print_pv) vl
  | Capp (s,[l;r]) when rs_equal s rs_func_app ->
      fprintf fmt (protect_on (pri > 5) "@[<hov 1>%a %a@]")
        print_pv l print_pv r
  | Capp (s,vl) when exec && c.cty_args = [] && ambig_cty s.rs_cty ->
      fprintf fmt (protect_on (pri > 0) "%a:%a")
        (print_capp 5 (Hrs.find_def ht_rs s s)) vl print_ity c.cty_result
  | Capp (s,vl) ->
      print_capp pri (Hrs.find_def ht_rs s s) fmt vl
  | Cpur (s,vl) when exec && c.cty_args = [] && ambig_ls s ->
      fprintf fmt (protect_on (pri > 0) "%a:%a")
        (print_cpur 5 s) vl print_ity c.cty_result
  | Cpur (s,vl) ->
      print_cpur pri s fmt vl

and print_enode pri fmt e = match e.e_node with
  | Evar v -> print_pv fmt v
  | Econst c -> print_const fmt c
  | Eexec c -> print_cexp true pri fmt c
  | Elet (LDvar (v,e1), e2)
    when v.pv_vs.vs_name.id_string = "_" && ity_equal v.pv_ity ity_unit ->
      fprintf fmt (protect_on (pri > 0) "%a;@\n%a")
        print_expr e1 print_expr e2
  | Elet (ld, e) ->
      fprintf fmt (protect_on (pri > 0) "%a@ in@\n%a")
        print_let_defn ld print_expr e;
      forget_let_defn ld
  | Eif (e0,e1,e2) when is_e_false e1 && is_e_true e2 ->
      fprintf fmt (protect_on (pri > 4) "not %a") (print_lexpr 4) e0
  | Eif (e0,e1,e2) when is_e_false e2 ->
      fprintf fmt (protect_on (pri > 3) "@[<hov 1>%a &&@ %a@]")
        (print_lexpr 4) e0 (print_lexpr 3) e1
  | Eif (e0,e1,e2) when is_e_true e1 ->
      fprintf fmt (protect_on (pri > 2) "@[<hov 1>%a ||@ %a@]")
        (print_lexpr 3) e0 (print_lexpr 2) e2
  | Eif (e0,e1,e2) when is_e_void e2 ->
      fprintf fmt (protect_on (pri > 0) "if %a then %a")
        print_expr e0 print_expr e1
  | Eif (e0,e1,e2) ->
      fprintf fmt (protect_on (pri > 0) "if %a then %a@ else %a")
        print_expr e0 print_expr e1 print_expr e2
  | Eassign al ->
      let print_left fmt (r,f,_) =
        fprintf fmt "%a.%a" print_pvty r print_rs f in
      let print_right fmt (_,_,v) = print_pv fmt v in
      fprintf fmt (protect_on (pri > 0) "%a <- %a")
        (Pp.print_list Pp.comma print_left) al
        (Pp.print_list Pp.comma print_right) al
  | Ecase (e0,bl) ->
      (* Elet and Ecase are ghost-containers *)
      fprintf fmt "match %a with@\n@[<hov>%a@]@\nend"
        print_expr e0 (Pp.print_list Pp.newline print_branch) bl
  | Ewhile (d,inv,varl,e) ->
      fprintf fmt "@[<hov 2>while %a do%a%a@\n%a@]@\ndone"
        print_expr d print_invariant inv print_variant varl print_expr e
  | Efor (pv,(pvfrom,dir,pvto),inv,e) ->
      fprintf fmt "@[<hov 2>for %a =@ %a@ %s@ %a@ %ado@\n%a@]@\ndone"
        print_pv pv print_pv pvfrom
        (if dir = To then "to" else "downto") print_pv pvto
        print_invariant inv print_expr e
  | Eraise (xs,e) when is_e_void e ->
      fprintf fmt "raise %a" print_xs xs
  | Eraise (xs,e) ->
      fprintf fmt "raise (%a %a)" print_xs xs print_expr e
  | Etry (e,bl) ->
      fprintf fmt "try %a with@\n@[<hov>%a@]@\nend"
        print_expr e (Pp.print_list Pp.newline print_xbranch) bl
  | Eabsurd ->
      fprintf fmt "absurd"
  | Eassert (Assert,f) ->
      fprintf fmt "assert { %a }" print_term f
  | Eassert (Assume,f) ->
      fprintf fmt "assume { %a }" print_term f
  | Eassert (Check,f) ->
      fprintf fmt "check { %a }" print_term f
  | Eghost e ->
      fprintf fmt "ghost ( %a )" print_expr e
  | Epure t ->
      fprintf fmt "pure { %a }" print_term t

and print_branch fmt ({pp_pat = p},e) =
  fprintf fmt "@[<hov 4>| %a ->@ %a@]" print_pat p print_expr e;
  Svs.iter forget_var p.pat_vars

and print_xbranch fmt (xs,v,e) =
  if Spv.mem v e.e_effect.eff_reads then begin
    fprintf fmt "@[<hov 4>| %a %a ->@ %a@]" print_xs xs print_pv v print_expr e;
    forget_pv v
  end else if ity_equal v.pv_ity ity_unit then
    fprintf fmt "@[<hov 4>| %a ->@ %a@]" print_xs xs print_expr e
  else
    fprintf fmt "@[<hov 4>| %a _ ->@ %a@]" print_xs xs print_expr e

and print_let_defn fmt = function
  | LDvar (v,e) ->
      fprintf fmt "@[<hov 2>let %s%a%a =@ %a@]"
        (if v.pv_ghost then "ghost " else "")
        print_pv v print_id_labels v.pv_vs.vs_name
        (print_lexpr 0 (*4*)) e
  | LDsym (s,{c_node = Cfun e; c_cty = ({cty_args = _::_} as c)}) ->
      fprintf fmt "@[<hov 2>let %a%a =@\n%a@]"
        print_rs_head s print_cty s.rs_cty (*FIXME: c*)
        (print_lexpr 0 (*4*)) e;
      forget_cty c
  | LDsym (s,{c_node = Cany; c_cty = ({cty_args = _::_} as c)}) ->
      fprintf fmt "@[<hov 2>val %a%a@]"
        print_rs_head s print_cty c;
      forget_cty c
  | LDsym (s,c) ->
      fprintf fmt "@[<hov 2>let %a =@\n%a@]"
        print_rs_head s
        (print_cexp false 0 (*4*)) c
  | LDrec rdl ->
      List.iter (fun fd -> Hrs.replace ht_rs fd.rec_rsym fd.rec_sym) rdl;
      Pp.print_list_next Pp.newline print_rec_fun fmt rdl;
      List.iter (fun fd -> Hrs.remove ht_rs fd.rec_rsym) rdl

and print_rec_fun fst fmt fd =
  let e = match fd.rec_fun.c_node with
    | Cfun e -> e | _ -> assert false in
  fprintf fmt "@[<hov 2>%s %a%a%a =@\n%a@]"
    (if fst then "let rec" else "with")
    print_rs_head fd.rec_sym
    print_cty fd.rec_fun.c_cty
    print_variant fd.rec_varl
    (print_lexpr 0 (*4*)) e;
  forget_cty fd.rec_fun.c_cty

(* exception handling *)

let () = Exn_printer.register (fun fmt e -> match e with
  | ConstructorExpected s -> fprintf fmt
      "Function %a is not a constructor" print_rs s
  | FieldExpected s -> fprintf fmt
      "Function %a is not a mutable field" print_rs s
  | _ -> raise e)
