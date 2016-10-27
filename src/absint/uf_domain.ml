open Domain
open Apron
open Term

module Make(S:sig
    module A:DOMAIN
    val env: Env.env
    val pmod: Pmodule.pmodule
  end) = struct
  module A = S.A
  module D = A
  
  module Ai_logic = Ai_logic.Make(struct
      let env = S.env
      let pmod = S.pmod
    end)
  open Ai_logic

  type domain = A.t

  exception Not_handled of Term.term

  (* utility function that make equivalent classes and sum the last component *)
  let sum_list a =
    let a = List.sort (fun (i, _) (j, _) ->
        compare i j) a in
    let rec merge = function
      | [] -> []
      | [b] -> [b]
      | (a, b)::(c, d)::q ->
        if a = c then
          merge ((a, b + d)::q)
        else
          (a, b) :: (merge ((c, d)::q))
    in
    merge a


  type uf_man = {
    variable_mapping: (Apron.Var.t, Term.term) Hashtbl.t;
    mutable apron_mapping: Var.t Term.Mterm.t;
    mutable region_mapping: (Ity.pvsymbol * Term.term) list Ity.Mreg.t;
    mutable env: Environment.t;
    mutable defined_terms: unit Term.Mterm.t;
  }

  type uf_t = unit

  type man = A.man * uf_man
  type env = unit
  type t = A.t * uf_t

  let create_manager () =
    A.create_manager (), { variable_mapping = Hashtbl.create 512;
                           apron_mapping = Term.Mterm.empty;
                           region_mapping = Ity.Mreg.empty;
                           env = Environment.make [||] [||];
                           defined_terms = Term.Mterm.empty; }

  let bottom (man, uf_man) env =
    A.bottom man uf_man.env, env

  let top (man, uf_man) env =
    A.top man uf_man.env, env

  let canonicalize (man, _) (a, b) =
    A.canonicalize man a

  let is_bottom (man, _) (a, b) =
    A.is_bottom man a

  let is_leq (man, _) (a, b) (c, d) =
    A.is_leq man a c

  let join (man, _) (a, b) (c, d) =
    A.join man a c, ()

  let join_list man l = match l with
    | [] -> assert false
    | t::q -> List.fold_left (join man) t q

  let widening (man, _) (a, b) (c, d) =
    A.widening man a c, ()

  let print fmt (a, b) = A.print fmt a

  let to_term env pmod (man, _) (a, b) v =
    A.to_term env pmod man a v

  let push_label (man, uf_man) env i (a, b) =
    A.push_label man uf_man.env i a, b
  
  let warning_t s t =
    Format.eprintf "-- warning: %s -- triggered by " s;
    Pretty.print_term Format.err_formatter t;
    Format.eprintf " of type ";
    Pretty.print_ty Format.err_formatter (Term.t_type t);
    Format.eprintf "@."

  let ident_ret = Ident.{pre_name = "$pat"; pre_label = Ident.Slab.empty; pre_loc = None; }
  let access_field constr constr_args a i (proj, t) =
      match a.t_node with
      | Tapp(func, args) when func.ls_constr = 1 ->
        List.nth args i
      | Tvar(_) | _ ->
        match proj with
        | None ->
          let return = create_vsymbol ident_ret t in
          let pat = List.mapi (fun k t ->
              if k = i then
                pat_var return
              else
                pat_wild t
            ) constr_args in
          t_case a [t_close_branch (pat_app constr pat (t_type a)) (t_var return)]
        | Some s ->
          t_app s [a] (Some t)

  
  let get_subvalues a ity =
    let open Ty in
    let myty = t_type a in
    let rec aux ity =
      match myty.ty_node with
      | _ when ty_equal myty ty_int || ty_equal myty ty_bool ->
        [a, None]
      | Tyapp(tys, vars) -> 
        begin
          let vars = Ty.ts_match_args tys vars in
          match (Ident.Mid.find tys.ts_name known_logical_ident).Decl.d_node with
          | Decl.Ddata([_, [ls, ls_projs]]) ->
            let l =
              let my_ls_args = List.map (fun i -> Ty.ty_inst vars i) ls.ls_args in
              List.combine my_ls_args ls_projs
              |> List.map (fun (arg_type, proj) ->
                  match proj with
                  | Some s ->  Some s,
                               (match s.ls_value with
                                | Some t ->
                                  let l = Ty.ty_inst vars t in
                                  assert (Ty.ty_equal l arg_type);
                                  l
                                | None -> assert false)
                  | None -> None, arg_type)
              |> List.mapi (access_field ls my_ls_args a)
            in
            begin
              match ity with
              | None -> List.map (fun a -> a, None) l
              | Some its ->
                let pdecl = Pdecl.((find_its_defn known_pdecl its).itd_fields) in
                List.map (fun a -> Some a) pdecl
                |> List.combine l
            end
          | Decl.Dtype({ts_def = Some _; ts_args = _; _ }) ->
            (* untested code*)
            let () = assert false in
            aux ity
          | Decl.Ddata([_; _]) ->
            warning_t "Multiple constructors is not supported in abstract interpretation." a; []
          | Decl.Ddata(_) ->
            warning_t "Recursive types is not supported in abstract interpretation." a; []
          | Decl.Dtype(_) -> (* This happens when a type is private or has an invariant: it can't be accesed
                              * by the logic, so we give up and only look for projections by looking
                              * at program projections. *)
            begin
              try
                let its = Ity.restore_its tys in
                (match ity with
                 | None -> ()
                 | Some s -> assert (Ity.its_equal its s));
                let pdecl = Pdecl.((find_its_defn known_pdecl its).itd_fields) in
                List.map (fun b ->
                    let l = match Expr.(b.rs_logic) with | Expr.RLls(l) -> l | _ -> assert false in
                    let this_ty = Expr.(Ity.(ty_of_ity b.rs_cty.cty_result)) in
                    let ty = Ty.ty_inst vars this_ty in
                    t_app l [a] (Some ty), if ity = None then None else Some b) pdecl
              with
              | Not_found -> failwith "could not restore its"
            end
          | Decl.Dind(_) ->
            warning_t "Could not find type declaration (got inductive predicate)."
              a;
            []
          | Decl.Dlogic(_) ->
            warning_t "Could not find type declaration (got logic declaration)."
              a;
            []
          | Decl.Dprop(_) ->
            warning_t "Could not find type declaration (got propsition) for: "
              a;
            []
          | Decl.Dparam(_) ->
            warning_t "Could not find type declaration (got param)."
              a;
            []
        end
      | Tyvar(_) ->
        warning_t "Comparison of values with an abstract type, the interpretation will not be precise" a;
        []
    in
    aux ity

  (** Get a set of (apron) linear expressions from a constraint stated in why3 logic.
   *
   * The resulting list of linear expressions is weaker than the original why3
   * formula.
   * In the most imprecise case, it returns an empty list.
   **)
  let meet_term: man -> Term.term -> (t -> t) = fun (man, uf_man) t ->
    let open Term in

    (* First inline everything, for instance needed for references
     * where !i is (!) i and must be replaced by (contents i) *)
    let t = t_replace_all t in

    (* Let's try to remove the nots that we can *)
    let t = t_descend_nots t in

    let var_of_term t =
      try
        Some (Term.Mterm.find t uf_man.apron_mapping)
      with
      | Not_found -> None
    in

    (* Assuming that t is an arithmetic term, this computes the number of ocurrence of variables
     * ando the constant of the arithmetic expression.
     * It returns (variables, constant)
     *
     * For instance, 4 + x + y set cst to 4, and constr to [(x, 1), (y, 1)]
     * *)
    let rec term_to_var_list coeff t =
      match t.t_node with
      | Tvar(_) ->
        begin
        match var_of_term t with
        | Some var -> ([(var, coeff)], 0)
        | None -> Format.eprintf "Variable undefined: "; Pretty.print_term Format.err_formatter t; Format.eprintf "@."; failwith "undefined var"
        end
      | Tconst(Number.ConstInt(n)) ->
        let n = Number.compute_int n in
        ([], coeff * (BigInt.to_int n))
      | Tapp(func, args) when Term.ls_equal func ad_int ->
        List.fold_left (fun (a, b) c ->
            let c, d = term_to_var_list coeff c in
            (a @ c, b + d)) ([], 0)args
      | Tapp(func, [a;b]) when Term.ls_equal func min_int ->
        let c, d = term_to_var_list coeff a in
        let e, f = term_to_var_list (-coeff) b in
        (c @ e, d + f)
      | Tapp(func, [a]) when Term.ls_equal func min_u_int ->
        term_to_var_list (-coeff)  a;
      | Tapp(func, [{t_node = Tconst(Number.ConstInt(n)); _}; a])
      | Tapp(func, [a; {t_node = Tconst(Number.ConstInt(n)); _};]) when Term.ls_equal func mult_int ->
        let n = Number.compute_int n in
        term_to_var_list ((BigInt.to_int n) * coeff) a
      (* FIXME: need a nice domain for algebraic types *)
      | _ -> (* maybe a record access *)
        begin
          match var_of_term t with
          | None -> Format.eprintf "Could not find term@."; raise (Not_handled t)
          | Some s ->
            ([s, coeff], 0)
        end
    in
    
    (* This takes an epsilon-free formula and returns a list of linear expressions weaker than
     * the original formula. *)
    let rec aux t =
      try
        match t.t_node with
        | Tbinop(Tand, a, b) ->
          let fa = aux a in
          let fb = aux b in
          (fun d ->
            fb (fa d))
        | Tbinop(Tor, a, b) ->
          let fa = aux a in
          let fb = aux b in
          (fun d ->
             let d1 = fa d in
             let d2 = fb d in
             D.join man d1 d2)
        | Tapp(func, [a; b]) when (Ty.ty_equal (t_type a) Ty.ty_int || Ty.ty_equal (t_type a) Ty.ty_bool)
          && 
          (ls_equal ps_equ func ||
           ls_equal lt_int func ||
           ls_equal gt_int func ||
           ls_equal le_int func ||
           ls_equal ge_int func)

          -> (* ATM, this is handled only for equality and integer comparison *)
          (* FIXME: >, <=, >=, booleans *)
            let base_coeff, eq_type =
              if ls_equal ps_equ func then
                1, Lincons1.EQ
              else if ls_equal lt_int func then
                1, Lincons1.SUP
              else if ls_equal gt_int func then
                -1, Lincons1.SUP
              else if ls_equal le_int func then
                1, Lincons1.SUPEQ
              else if ls_equal ge_int func then
                -1, Lincons1.SUPEQ
              else
                assert false
            in
            let va, ca = term_to_var_list (-base_coeff) a in
            let vb, cb = term_to_var_list base_coeff b in
            let c = ca + cb in
            let v = sum_list (va @ vb) in
            let expr = Linexpr1.make uf_man.env in
            let constr = List.map (fun (var, coeff) ->
                Coeff.Scalar (Scalar.of_int coeff), var) v in
            Linexpr1.set_list expr constr None;
            let cons = Lincons1.make expr eq_type in
            Lincons1.set_cst cons (Coeff.Scalar (Scalar.of_int c));
            let arr = Lincons1.array_make uf_man.env 1 in
            Lincons1.array_set arr 0 cons;
              (fun d ->
                 D.meet_lincons_array man d arr)
        | Tapp(func, [a;b]) when ls_equal ps_equ func ->
          begin
            let subv_a = get_subvalues a None in
            let subv_b = get_subvalues b None in
            List.combine subv_a subv_b 
            |> List.fold_left (fun f ((a, _), (b, _)) ->
                let g = aux (t_app ps_equ [a; b] None) in
                (fun abs ->
                   f (g (abs)))) (fun abs -> abs)
          end
        | Tif(a, b, c) ->
          let fa = aux a in
          let fa_not = aux (t_descend_nots a) in
          let fb = aux b in
          let fc = aux c in
          (fun d ->
             let d1 = fb (fa d) in
             let d2 = fc (fa_not d) in
             D.join man d1 d2)
        | Ttrue -> (fun d -> d)
        | _ when t_equal t t_bool_true || t_equal t t_true -> (fun d -> d)
        | Tfalse -> (fun _ -> D.bottom man uf_man.env)
        | _ when t_equal t t_bool_false || t_equal t t_false -> (fun _ -> D.bottom man uf_man.env)
        | _ ->
          raise (Not_handled t)
      with
      | Not_handled(t) ->
        Format.eprintf "Couldn't understand entirely the post condition: ";
        Pretty.print_term Format.err_formatter t;
        Format.eprintf "@.";
        (fun d -> d)
    in
    try
      let f = aux t in
    (fun (a, b) -> f a, b)
    with
    | e ->
      Format.eprintf "error while computing domain for post conditions: ";
      Pretty.print_term Format.err_formatter t;
      Format.eprintf "@.";
      raise e

  let var_id = ref 0

  let ensure_variable uf_man v t =
    if not (Environment.mem_var uf_man.env v) then
      begin
        Hashtbl.add uf_man.variable_mapping v t;
        uf_man.env <- Environment.add uf_man.env [|v|] [||]
      end
  
  let add_lvariable_to_env (man, uf_man) vsym =
    incr var_id;
    let open Expr in
    let open Ity in
    let open Ty in
    let logical_term = t_var vsym in
    try
      let _ = Mterm.find logical_term uf_man.defined_terms in
      ()
    with
    | Not_found ->
      uf_man.defined_terms <- Mterm.add logical_term () uf_man.defined_terms;
      ignore (Format.flush_str_formatter ());
      if Ty.ty_equal (t_type logical_term) ty_int then
        begin
          Format.eprintf " added@.";
          let reg_name = Pretty.print_term Format.str_formatter logical_term
                         |> Format.flush_str_formatter
                         |> Format.sprintf "%d%s" !var_id in
          let v =
            Var.of_string reg_name in
          assert (not (Environment.mem_var uf_man.env v));
          ensure_variable uf_man v logical_term;
          uf_man.apron_mapping <- Term.Mterm.add logical_term v uf_man.apron_mapping
        end
      else if Ty.ty_equal (t_type logical_term) ty_bool then
        begin
          let reg_name = Pretty.print_term Format.str_formatter logical_term
                         |> Format.flush_str_formatter
                         |> Format.sprintf "%d%s" !var_id in
          let v =
            Var.of_string reg_name in
          assert (not (Environment.mem_var uf_man.env v));
          ensure_variable uf_man v logical_term;
          uf_man.apron_mapping <- Term.Mterm.add logical_term v uf_man.apron_mapping;
        end
      else
        begin
          let reg_name = Pretty.print_term Format.str_formatter logical_term
                         |> Format.flush_str_formatter in
          let subv = get_subvalues logical_term None in
          List.iter (fun (t, _) ->
              ignore (Format.flush_str_formatter ());
              let v = Pretty.print_term Format.str_formatter t
                      |> Format.flush_str_formatter
                      |> Format.sprintf "%d%s.%s" !var_id reg_name
                      |> Var.of_string
              in
              ensure_variable uf_man v t;
              uf_man.apron_mapping <- Term.Mterm.add t v uf_man.apron_mapping) subv
        end

  
  let cached_vreturn = ref (Ty.Mty.empty)
  let ident_ret = Ident.{pre_name = "$reg"; pre_label = Ident.Slab.empty; pre_loc = None; }
  let create_vreturn man ty =
    try
      Ty.Mty.find ty !cached_vreturn
    with
    | Not_found ->
      let v  = Term.create_vsymbol ident_ret ty in
      add_lvariable_to_env man v;
      cached_vreturn := Ty.Mty.add ty v !cached_vreturn;
      v

  let add_variable_to_env (man, uf_man) psym =
    incr var_id;
    let open Expr in
    let open Ity in
    let open Ty in
    let variable_type = Ity.(psym.pv_ity) in
    let logical_term =
      match Expr.term_of_expr ~prop:false (Expr.e_var psym) with
      | Some s -> s
      | None -> assert false
    in
    ignore (Format.flush_str_formatter ());
    match Ity.(variable_type.ity_node), (Term.t_type logical_term).ty_node with
    | _ when Ty.ty_equal (t_type logical_term) ty_int ->
      let reg_name = Pretty.print_term Format.str_formatter logical_term
                     |> Format.flush_str_formatter
                     |> Format.sprintf "%d%s" !var_id in
      let v =
        Var.of_string reg_name in
      assert (not (Environment.mem_var uf_man.env v));
      ensure_variable uf_man v logical_term;
      uf_man.apron_mapping <- Term.Mterm.add logical_term v uf_man.apron_mapping
    | _ when Ty.ty_equal (t_type logical_term) ty_bool ->
      let reg_name = Pretty.print_term Format.str_formatter logical_term
                     |> Format.flush_str_formatter
                     |> Format.sprintf "%d%s" !var_id in
      let v =
        Var.of_string reg_name in
      assert (not (Environment.mem_var uf_man.env v));
      ensure_variable uf_man v logical_term;
      uf_man.apron_mapping <- Term.Mterm.add logical_term v uf_man.apron_mapping;
    | _ when Ity.ity_equal variable_type Ity.ity_unit
      -> ()
    | Ity.Ityreg(reg), Tyapp(_, _) -> 
      begin
        let reg_name = 
          Ity.print_reg_name Format.str_formatter reg
          |> Format.flush_str_formatter
        in
        let vret = create_vreturn (man, uf_man) (t_type logical_term) in
        let vret = t_var vret in
        let subv = get_subvalues vret (Some reg.reg_its) in
        let subv_r = get_subvalues logical_term (Some reg.reg_its) in
        let subv = List.combine subv subv_r in
        let proj_list =
          List.fold_left (fun acc ((generic_region_term, pfield), (real_term, _)) ->
              let pfield = match pfield with
                | Some s -> s
                | None -> assert false
              in

              ignore (Format.flush_str_formatter ());
              let v = Pretty.print_term Format.str_formatter generic_region_term
                      |> Format.flush_str_formatter
                      |> Format.sprintf "r$%s.%s" reg_name
                      |> Var.of_string
              in
              ensure_variable uf_man v real_term;
              let accessor = match pfield.rs_field with
                | Some s -> s
                | None -> assert false
              in
              uf_man.apron_mapping <- Term.Mterm.add real_term v uf_man.apron_mapping;
              (accessor, real_term) :: acc
            ) [] subv
        in
        uf_man.region_mapping <- Ity.Mreg.add reg proj_list uf_man.region_mapping
      end
    | Ity.Ityapp(_), _ ->
      Format.eprintf "Let's check that ";
      Ity.print_ity Format.err_formatter variable_type;
      Format.eprintf " has only non mutable fields.";
      let reg_name = Ity.print_pv Format.str_formatter psym
                     |> Format.flush_str_formatter in
      let subv = get_subvalues logical_term None in
      List.iter (fun (t, _) ->
          ignore (Format.flush_str_formatter ());
          let v = Pretty.print_term Format.str_formatter t
                  |> Format.flush_str_formatter
                  |> Format.sprintf "%d%s.%s" !var_id reg_name
                  |> Var.of_string
          in
          ensure_variable uf_man v t;
          uf_man.apron_mapping <- Term.Mterm.add t v uf_man.apron_mapping) subv;
    | _ ->
      (* We can safely give up on a, as no integer variable can descend from it (because it is well typed) *)
      Format.eprintf "Variable could not be added properly: ";
      Pretty.print_term Format.err_formatter logical_term;
      Format.eprintf " of type ";
      Ity.print_ity Format.err_formatter variable_type;
      Format.eprintf "@.";
      ()

  let forget_term (man, uf_man) t =
      let vars_to_forget =
        get_subvalues t None
        |> List.map (fun (a, _) -> Term.Mterm.find a uf_man.apron_mapping)
        |> Array.of_list
      in
      (fun (abs, a) -> 
          D.forget_array man abs vars_to_forget false, ()
      )

  let forget_var m v = forget_term m (t_var v)

  let forget_region (man, uf_man) v b =
    let terms = Ity.Mreg.find v uf_man.region_mapping in
    let members =
      Ity.Mpv.fold_left (fun acc c () ->
          let _, t =
            try
              List.find (fun (p, _) ->
                  Ity.pv_equal p c) terms
            with
            | Not_found ->
              Format.eprintf "Couldn't find projection for field ";
              Ity.print_pv Format.err_formatter c;
              Format.eprintf "@.";
              Format.eprintf "(known fields: ";
              List.iter (fun (p, _) ->
                  Ity.print_pv Format.err_formatter p;
                  Format.eprintf " @.";
                ) terms;
              Format.eprintf ")@.";
              assert false
          in
          t::acc
        ) [] b in
    List.fold_left (fun f t ->
        let a = forget_term (man, uf_man) t in
        fun x -> f x |> a) (fun x -> x) members

  let to_term (man, uf_man) (a, b) =
    D.to_term S.env S.pmod man a (fun a ->
        try
          Hashtbl.find uf_man.variable_mapping a
        with 
        | Not_found ->
          Format.eprintf "Couldn't find variable %s@." (Var.to_string a);
          raise Not_found
      )
end
