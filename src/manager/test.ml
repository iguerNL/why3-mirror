
open Format
open Why
open Whyconf

(*
let autodetection () = 
  let alt_ergo = {
    name    = "Alt-Ergo";
    command = "alt-ergo %s";
    driver  = "drivers/alt_ergo.drv" }
  in
  let z3 = {
    name    = "Z3";
    command = "z3 -smt -in";
    driver  = "drivers/z3.drv" }
  in
  let cvc3 = {
    name    = "CVC3";
    command = "cvc3 -lang smt";
    driver  = "drivers/cvc3.drv" }
  in
  let coq = {
    name    = "Coq";
    command = "coqc %s";
    driver  = "drivers/coq.drv" }
  in
  let provers = Util.Mstr.empty in
  let provers = Util.Mstr.add "alt-ergo" alt_ergo provers in
  let provers = Util.Mstr.add "z3" z3 provers in
  let provers = Util.Mstr.add "cvc3" cvc3 provers in
  let provers = Util.Mstr.add "coq" coq provers in
  let config = {
    conf_file = "why.conf";
    loadpath  = ["theories"];
    timelimit = Some 2;
    memlimit  = None;
    provers   = provers }
  in
  save_config config
*)

let config = 
  try 
    Whyconf.read_config None
  with 
      Not_found -> 
        eprintf "No config file found.@.";
(* "Running autodetection of provers.@.";
        autodetection ();
*)
        exit 1
    | Whyconf.Error e ->
        eprintf "Error while reading config file: %a@." Whyconf.report e;
        exit 1

let () = printf "Load path is: %a@." (Pp.print_list Pp.comma Pp.string) config.loadpath

let env = Why.Env.create_env (Why.Typing.retrieve config.loadpath)

let fname = "tests/test-claude"

let () = Db.init_base (fname ^ ".db")

let get_driver name = 
  let pi = Util.Mstr.find name config.provers in
  Why.Driver.load_driver pi.Whyconf.driver env

type prover_data =
    { prover : Db.prover;
      command : string;
      driver : Why.Driver.driver;
    }

let provers_data =
  printf "Provers: ";
  let l = 
    Util.Mstr.fold
    (fun id conf acc ->
       let name = conf.Whyconf.name in
       printf " %s, " name;
       { prover = Db.get_prover name;
         command = conf.Whyconf.command;
         driver = get_driver id; } :: acc
    ) config.provers []
  in
  printf "@.";
  l
   

let timelimit = 
match config.timelimit with
| None -> 2
| Some n -> n

let () = 
  printf "previously known goals:@\n";
  List.iter (fun s -> printf "%s@\n" (Db.goal_task_checksum s)) (Db.root_goals ());
  printf "@."
   
let rec report fmt = function
  | Lexer.Error e ->
      fprintf fmt "lexical error: %a" Lexer.report e;
  | Loc.Located (loc, e) ->
      fprintf fmt "%a%a" Loc.report_position loc report e
  | Parsing.Parse_error ->
      fprintf fmt "syntax error"
  | Denv.Error e ->
      Denv.report fmt e
  | Typing.Error e ->
      Typing.report fmt e
  | Decl.UnknownIdent i ->
      fprintf fmt "anomaly: unknown ident '%s'" i.Ident.id_short
  | Driver.Error e ->
      Driver.report fmt e
  | Config.Dynlink.Error e ->
      fprintf fmt "Dynlink : %s" (Config.Dynlink.error_message e)
  | e -> fprintf fmt "anomaly: %s" (Printexc.to_string e)


let m : Why.Theory.theory Why.Theory.Mnm.t =
  try
    let cin = open_in (fname ^ ".why") in
    let m = Why.Typing.read_channel env fname cin in
    close_in cin;
    eprintf "Parsing/Typing Ok@.";
    m
  with e -> 
    eprintf "%a@." report e;
    exit 1



let add_task (tname : string) (task : Why.Task.task) acc =
  match task with
    | None -> assert false
    | Some t ->
        match t.Why.Task.task_decl with
          | Why.Task.Use _ | Why.Task.Clone _ -> assert false
          | Why.Task.Decl d ->
              match d.Why.Decl.d_node with
                | Why.Decl.Dtype _ | Why.Decl.Dlogic _ | Why.Decl.Dind _ -> assert false
                | Why.Decl.Dprop (_kind,name,_f) ->
                    eprintf "doing task: tname=%s, name=%s@." tname
                      name.Why.Decl.pr_name.Why.Ident.id_long;
                    Db.add_or_replace_task name task :: acc

let do_theory tname th glist =
(*
  let add acc (x,l) =
    let pr = try Why.Theory.ns_find_pr th.Why.Theory.th_export l with Not_found ->
      Format.eprintf "Goal '%s' not found in theory '%s'.@." x tname;
      exit 1
    in
    Why.Decl.Spr.add pr acc
  in
*)
(*
  let prs = Some (Queue.fold add Why.Decl.Spr.empty glist) in
  let prs = if Queue.is_empty glist then None else prs in
*)
  let tasks = Why.Task.split_theory th None in
  List.fold_right (add_task tname) tasks glist


(*
  if !opt_prove then begin
    let res = Driver.call_prover ~debug:!opt_debug ?timeout drv task in
    printf "%s %s %s : %a@." fname tname
      ((task_goal task).Decl.pr_name).Ident.id_long
      Call_provers.print_prover_result res
  end else match !opt_output with
    | None ->
        printf "@[%a@]@?" (Driver.print_task drv) task
    | Some dir ->
        let file =
          let file = Filename.basename fname in
          try Filename.chop_extension file
          with Invalid_argument _ -> file
        in
        let tname = th.th_name.Ident.id_short in
        let dest = Driver.filename_of_goal drv file tname task in
        (* Uniquify the filename before the extension if it exists*)
        let i = try String.rindex dest '.' with _ -> String.length dest in
        let name = Ident.string_unique !fname_printer (String.sub dest 0 i) in
        let ext = String.sub dest i (String.length dest - i) in
        let cout = open_out (Filename.concat dir (name ^ ext)) in
        let fmt = formatter_of_out_channel cout in
        fprintf fmt "@[%a@]@?" (Driver.print_task drv) task;
        close_out cout
*)

let goal_menu g = 
  try
    while true do 
      printf "Menu:@.";
      let _,menu = List.fold_left
        (fun (i,acc) p -> 
           let i = succ i in
           printf "%2d: try %s@." i (Db.prover_name p.prover);
           (i,(i,p)::acc)) (0,[]) provers_data
      in
      printf "Select a choice:@.";
      let s = read_line () in
      (try 
         let i = try int_of_string s with Failure _ -> raise Not_found in
         let p = List.assoc i menu in
         let call = 
	   try
             Db.try_prover ~debug:true ~timelimit ~memlimit:0 
               ~prover:p.prover ~command:p.command ~driver:p.driver g 
           with Db.AlreadyAttempted ->
             printf "Proof already attempted, no need to rerun@.";
             raise Exit
	 in
         call ();
         raise Exit
       with Not_found -> 
         printf "unknown choice@.");
    done
  with Exit -> ()
    
let main_loop goals =
  try
    while true do
      printf "Menu:@.";
      printf " 0: exit@.";
      let _,menu = List.fold_left
        (fun (i,acc) g -> 
           let i = succ i in
           printf "%2d: name='%s', proved=%b@." i (Db.goal_name g) (Db.goal_proved g);
           (i,(i,g)::acc)) (0,[]) goals
      in
      printf "Select a choice:@.";
      let s = read_line () in
      (try 
         let i = int_of_string s in
         if i=0 then raise Exit; 
         goal_menu (List.assoc i menu)
       with Not_found | Failure _ -> 
         printf "unknown choice@.");
    done
  with Exit -> ()
  
let () =
  eprintf "looking for goals@.";
(*
  let glist = Queue.create () in
*)
  let add_th t th mi = 
    eprintf "adding theory %s, %s@." th.Why.Theory.th_name.Why.Ident.id_long t;
    Why.Ident.Mid.add th.Why.Theory.th_name (t,th) mi 
  in
  let do_th _ (t,th) glist = 
    eprintf "doing theory %s, %s@." th.Why.Theory.th_name.Why.Ident.id_long t;
    do_theory t th glist  
  in
  let goals = 
    Why.Ident.Mid.fold do_th (Why.Theory.Mnm.fold add_th m Why.Ident.Mid.empty) []
  in
  eprintf "Production of goals done@.";
  try
    main_loop goals
  with Exit -> eprintf "Exiting...@."




(*
Local Variables: 
compile-command: "make -C ../.. bin/manager.byte"
End: 
*)




