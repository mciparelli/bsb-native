module Depend : sig 
#1 "../../ocaml/tools/depend.mli"
(***********************************************************************)
(*                                                                     *)
(*                                OCaml                                *)
(*                                                                     *)
(*            Xavier Leroy, projet Cristal, INRIA Rocquencourt         *)
(*                                                                     *)
(*  Copyright 1999 Institut National de Recherche en Informatique et   *)
(*  en Automatique.  All rights reserved.  This file is distributed    *)
(*  under the terms of the Q Public License version 1.0.               *)
(*                                                                     *)
(***********************************************************************)

(** Module dependencies. *)

module StringSet : Set.S with type elt = string

val free_structure_names : StringSet.t ref

val open_module : StringSet.t -> Longident.t -> unit

val add_use_file : StringSet.t -> Parsetree.toplevel_phrase list -> unit

val add_signature : StringSet.t -> Parsetree.signature -> unit

val add_implementation : StringSet.t -> Parsetree.structure -> unit

end = struct
#1 "../../ocaml/tools/depend.ml"
(***********************************************************************)
(*                                                                     *)
(*                                OCaml                                *)
(*                                                                     *)
(*            Xavier Leroy, projet Cristal, INRIA Rocquencourt         *)
(*                                                                     *)
(*  Copyright 1999 Institut National de Recherche en Informatique et   *)
(*  en Automatique.  All rights reserved.  This file is distributed    *)
(*  under the terms of the Q Public License version 1.0.               *)
(*                                                                     *)
(***********************************************************************)

open Asttypes
open Location
open Longident
open Parsetree

module StringSet = Set.Make(struct type t = string let compare = compare end)

(* Collect free module identifiers in the a.s.t. *)

let free_structure_names = ref StringSet.empty

let rec add_path bv = function
  | Lident s ->
      if not (StringSet.mem s bv)
      then free_structure_names := StringSet.add s !free_structure_names
  | Ldot(l, _s) -> add_path bv l
  | Lapply(l1, l2) -> add_path bv l1; add_path bv l2

let open_module bv lid = add_path bv lid

let add bv lid =
  match lid.txt with
    Ldot(l, _s) -> add_path bv l
  | _ -> ()

let addmodule bv lid = add_path bv lid.txt

let rec add_type bv ty =
  match ty.ptyp_desc with
    Ptyp_any -> ()
  | Ptyp_var _ -> ()
  | Ptyp_arrow(_, t1, t2) -> add_type bv t1; add_type bv t2
  | Ptyp_tuple tl -> List.iter (add_type bv) tl
  | Ptyp_constr(c, tl) -> add bv c; List.iter (add_type bv) tl
  | Ptyp_object (fl, _) -> List.iter (fun (_, _, t) -> add_type bv t) fl
  | Ptyp_class(c, tl) -> add bv c; List.iter (add_type bv) tl
  | Ptyp_alias(t, _) -> add_type bv t
  | Ptyp_variant(fl, _, _) ->
      List.iter
        (function Rtag(_,_,_,stl) -> List.iter (add_type bv) stl
          | Rinherit sty -> add_type bv sty)
        fl
  | Ptyp_poly(_, t) -> add_type bv t
  | Ptyp_package pt -> add_package_type bv pt
  | Ptyp_extension _ -> ()

and add_package_type bv (lid, l) =
  add bv lid;
  List.iter (add_type bv) (List.map (fun (_, e) -> e) l)

let add_opt add_fn bv = function
    None -> ()
  | Some x -> add_fn bv x

let add_constructor_decl bv pcd =
  List.iter (add_type bv) pcd.pcd_args; Misc.may (add_type bv) pcd.pcd_res

let add_type_declaration bv td =
  List.iter
    (fun (ty1, ty2, _) -> add_type bv ty1; add_type bv ty2)
    td.ptype_cstrs;
  add_opt add_type bv td.ptype_manifest;
  let add_tkind = function
    Ptype_abstract -> ()
  | Ptype_variant cstrs ->
      List.iter (add_constructor_decl bv) cstrs
  | Ptype_record lbls ->
      List.iter (fun pld -> add_type bv pld.pld_type) lbls
  | Ptype_open -> () in
  add_tkind td.ptype_kind

let add_extension_constructor bv ext =
  match ext.pext_kind with
      Pext_decl(args, rty) ->
        List.iter (add_type bv) args; Misc.may (add_type bv) rty
    | Pext_rebind lid -> add bv lid

let add_type_extension bv te =
  add bv te.ptyext_path;
  List.iter (add_extension_constructor bv) te.ptyext_constructors

let rec add_class_type bv cty =
  match cty.pcty_desc with
    Pcty_constr(l, tyl) ->
      add bv l; List.iter (add_type bv) tyl
  | Pcty_signature { pcsig_self = ty; pcsig_fields = fieldl } ->
      add_type bv ty;
      List.iter (add_class_type_field bv) fieldl
  | Pcty_arrow(_, ty1, cty2) ->
      add_type bv ty1; add_class_type bv cty2
  | Pcty_extension _ -> ()

and add_class_type_field bv pctf =
  match pctf.pctf_desc with
    Pctf_inherit cty -> add_class_type bv cty
  | Pctf_val(_, _, _, ty) -> add_type bv ty
  | Pctf_method(_, _, _, ty) -> add_type bv ty
  | Pctf_constraint(ty1, ty2) -> add_type bv ty1; add_type bv ty2
  | Pctf_attribute _ -> ()
  | Pctf_extension _ -> ()

let add_class_description bv infos =
  add_class_type bv infos.pci_expr

let add_class_type_declaration = add_class_description

let pattern_bv = ref StringSet.empty

let rec add_pattern bv pat =
  match pat.ppat_desc with
    Ppat_any -> ()
  | Ppat_var _ -> ()
  | Ppat_alias(p, _) -> add_pattern bv p
  | Ppat_interval _
  | Ppat_constant _ -> ()
  | Ppat_tuple pl -> List.iter (add_pattern bv) pl
  | Ppat_construct(c, op) -> add bv c; add_opt add_pattern bv op
  | Ppat_record(pl, _) ->
      List.iter (fun (lbl, p) -> add bv lbl; add_pattern bv p) pl
  | Ppat_array pl -> List.iter (add_pattern bv) pl
  | Ppat_or(p1, p2) -> add_pattern bv p1; add_pattern bv p2
  | Ppat_constraint(p, ty) -> add_pattern bv p; add_type bv ty
  | Ppat_variant(_, op) -> add_opt add_pattern bv op
  | Ppat_type li -> add bv li
  | Ppat_lazy p -> add_pattern bv p
  | Ppat_unpack id -> pattern_bv := StringSet.add id.txt !pattern_bv
  | Ppat_exception p -> add_pattern bv p
  | Ppat_extension _ -> ()

let add_pattern bv pat =
  pattern_bv := bv;
  add_pattern bv pat;
  !pattern_bv

let rec add_expr bv exp =
  match exp.pexp_desc with
    Pexp_ident l -> add bv l
  | Pexp_constant _ -> ()
  | Pexp_let(rf, pel, e) ->
      let bv = add_bindings rf bv pel in add_expr bv e
  | Pexp_fun (_, opte, p, e) ->
      add_opt add_expr bv opte; add_expr (add_pattern bv p) e
  | Pexp_function pel ->
      add_cases bv pel
  | Pexp_apply(e, el) ->
      add_expr bv e; List.iter (fun (_,e) -> add_expr bv e) el
  | Pexp_match(e, pel) -> add_expr bv e; add_cases bv pel
  | Pexp_try(e, pel) -> add_expr bv e; add_cases bv pel
  | Pexp_tuple el -> List.iter (add_expr bv) el
  | Pexp_construct(c, opte) -> add bv c; add_opt add_expr bv opte
  | Pexp_variant(_, opte) -> add_opt add_expr bv opte
  | Pexp_record(lblel, opte) ->
      List.iter (fun (lbl, e) -> add bv lbl; add_expr bv e) lblel;
      add_opt add_expr bv opte
  | Pexp_field(e, fld) -> add_expr bv e; add bv fld
  | Pexp_setfield(e1, fld, e2) -> add_expr bv e1; add bv fld; add_expr bv e2
  | Pexp_array el -> List.iter (add_expr bv) el
  | Pexp_ifthenelse(e1, e2, opte3) ->
      add_expr bv e1; add_expr bv e2; add_opt add_expr bv opte3
  | Pexp_sequence(e1, e2) -> add_expr bv e1; add_expr bv e2
  | Pexp_while(e1, e2) -> add_expr bv e1; add_expr bv e2
  | Pexp_for( _, e1, e2, _, e3) ->
      add_expr bv e1; add_expr bv e2; add_expr bv e3
  | Pexp_coerce(e1, oty2, ty3) ->
      add_expr bv e1;
      add_opt add_type bv oty2;
      add_type bv ty3
  | Pexp_constraint(e1, ty2) ->
      add_expr bv e1;
      add_type bv ty2
  | Pexp_send(e, _m) -> add_expr bv e
  | Pexp_new li -> add bv li
  | Pexp_setinstvar(_v, e) -> add_expr bv e
  | Pexp_override sel -> List.iter (fun (_s, e) -> add_expr bv e) sel
  | Pexp_letmodule(id, m, e) ->
      add_module bv m; add_expr (StringSet.add id.txt bv) e
  | Pexp_assert (e) -> add_expr bv e
  | Pexp_lazy (e) -> add_expr bv e
  | Pexp_poly (e, t) -> add_expr bv e; add_opt add_type bv t
  | Pexp_object { pcstr_self = pat; pcstr_fields = fieldl } ->
      let bv = add_pattern bv pat in List.iter (add_class_field bv) fieldl
  | Pexp_newtype (_, e) -> add_expr bv e
  | Pexp_pack m -> add_module bv m
  | Pexp_open (_ovf, m, e) -> open_module bv m.txt; add_expr bv e
  | Pexp_extension _ -> ()

and add_cases bv cases =
  List.iter (add_case bv) cases

and add_case bv {pc_lhs; pc_guard; pc_rhs} =
  let bv = add_pattern bv pc_lhs in
  add_opt add_expr bv pc_guard;
  add_expr bv pc_rhs

and add_bindings recf bv pel =
  let bv' = List.fold_left (fun bv x -> add_pattern bv x.pvb_pat) bv pel in
  let bv = if recf = Recursive then bv' else bv in
  List.iter (fun x -> add_expr bv x.pvb_expr) pel;
  bv'

and add_modtype bv mty =
  match mty.pmty_desc with
    Pmty_ident l -> add bv l
  | Pmty_alias l -> addmodule bv l
  | Pmty_signature s -> add_signature bv s
  | Pmty_functor(id, mty1, mty2) ->
      Misc.may (add_modtype bv) mty1;
      add_modtype (StringSet.add id.txt bv) mty2
  | Pmty_with(mty, cstrl) ->
      add_modtype bv mty;
      List.iter
        (function
          | Pwith_type (_, td) -> add_type_declaration bv td
          | Pwith_module (_, lid) -> addmodule bv lid
          | Pwith_typesubst td -> add_type_declaration bv td
          | Pwith_modsubst (_, lid) -> addmodule bv lid
        )
        cstrl
  | Pmty_typeof m -> add_module bv m
  | Pmty_extension _ -> ()

and add_signature bv = function
    [] -> ()
  | item :: rem -> add_signature (add_sig_item bv item) rem

and add_sig_item bv item =
  match item.psig_desc with
    Psig_value vd ->
      add_type bv vd.pval_type; bv
  | Psig_type dcls ->
      List.iter (add_type_declaration bv) dcls; bv
  | Psig_typext te ->
      add_type_extension bv te; bv
  | Psig_exception pext ->
      add_extension_constructor bv pext; bv
  | Psig_module pmd ->
      add_modtype bv pmd.pmd_type; StringSet.add pmd.pmd_name.txt bv
  | Psig_recmodule decls ->
      let bv' =
        List.fold_right StringSet.add
                        (List.map (fun pmd -> pmd.pmd_name.txt) decls) bv
      in
      List.iter (fun pmd -> add_modtype bv' pmd.pmd_type) decls;
      bv'
  | Psig_modtype x ->
      begin match x.pmtd_type with
        None -> ()
      | Some mty -> add_modtype bv mty
      end;
      bv
  | Psig_open od ->
      open_module bv od.popen_lid.txt; bv
  | Psig_include incl ->
      add_modtype bv incl.pincl_mod; bv
  | Psig_class cdl ->
      List.iter (add_class_description bv) cdl; bv
  | Psig_class_type cdtl ->
      List.iter (add_class_type_declaration bv) cdtl; bv
  | Psig_attribute _ | Psig_extension _ ->
      bv

and add_module bv modl =
  match modl.pmod_desc with
    Pmod_ident l -> addmodule bv l
  | Pmod_structure s -> ignore (add_structure bv s)
  | Pmod_functor(id, mty, modl) ->
      Misc.may (add_modtype bv) mty;
      add_module (StringSet.add id.txt bv) modl
  | Pmod_apply(mod1, mod2) ->
      add_module bv mod1; add_module bv mod2
  | Pmod_constraint(modl, mty) ->
      add_module bv modl; add_modtype bv mty
  | Pmod_unpack(e) ->
      add_expr bv e
  | Pmod_extension _ ->
      ()

and add_structure bv item_list =
  List.fold_left add_struct_item bv item_list

and add_struct_item bv item =
  match item.pstr_desc with
    Pstr_eval (e, _attrs) ->
      add_expr bv e; bv
  | Pstr_value(rf, pel) ->
      let bv = add_bindings rf bv pel in bv
  | Pstr_primitive vd ->
      add_type bv vd.pval_type; bv
  | Pstr_type dcls ->
      List.iter (add_type_declaration bv) dcls; bv
  | Pstr_typext te ->
      add_type_extension bv te;
      bv
  | Pstr_exception pext ->
      add_extension_constructor bv pext; bv
  | Pstr_module x ->
      add_module bv x.pmb_expr; StringSet.add x.pmb_name.txt bv
  | Pstr_recmodule bindings ->
      let bv' =
        List.fold_right StringSet.add
          (List.map (fun x -> x.pmb_name.txt) bindings) bv in
      List.iter
        (fun x -> add_module bv' x.pmb_expr)
        bindings;
      bv'
  | Pstr_modtype x ->
      begin match x.pmtd_type with
        None -> ()
      | Some mty -> add_modtype bv mty
      end;
      bv
  | Pstr_open od ->
      open_module bv od.popen_lid.txt; bv
  | Pstr_class cdl ->
      List.iter (add_class_declaration bv) cdl; bv
  | Pstr_class_type cdtl ->
      List.iter (add_class_type_declaration bv) cdtl; bv
  | Pstr_include incl ->
      add_module bv incl.pincl_mod; bv
  | Pstr_attribute _ | Pstr_extension _ ->
      bv

and add_use_file bv top_phrs =
  ignore (List.fold_left add_top_phrase bv top_phrs)

and add_implementation bv l =
  ignore (add_structure bv l)

and add_top_phrase bv = function
  | Ptop_def str -> add_structure bv str
  | Ptop_dir (_, _) -> bv

and add_class_expr bv ce =
  match ce.pcl_desc with
    Pcl_constr(l, tyl) ->
      add bv l; List.iter (add_type bv) tyl
  | Pcl_structure { pcstr_self = pat; pcstr_fields = fieldl } ->
      let bv = add_pattern bv pat in List.iter (add_class_field bv) fieldl
  | Pcl_fun(_, opte, pat, ce) ->
      add_opt add_expr bv opte;
      let bv = add_pattern bv pat in add_class_expr bv ce
  | Pcl_apply(ce, exprl) ->
      add_class_expr bv ce; List.iter (fun (_,e) -> add_expr bv e) exprl
  | Pcl_let(rf, pel, ce) ->
      let bv = add_bindings rf bv pel in add_class_expr bv ce
  | Pcl_constraint(ce, ct) ->
      add_class_expr bv ce; add_class_type bv ct
  | Pcl_extension _ -> ()

and add_class_field bv pcf =
  match pcf.pcf_desc with
    Pcf_inherit(_, ce, _) -> add_class_expr bv ce
  | Pcf_val(_, _, Cfk_concrete (_, e))
  | Pcf_method(_, _, Cfk_concrete (_, e)) -> add_expr bv e
  | Pcf_val(_, _, Cfk_virtual ty)
  | Pcf_method(_, _, Cfk_virtual ty) -> add_type bv ty
  | Pcf_constraint(ty1, ty2) -> add_type bv ty1; add_type bv ty2
  | Pcf_initializer e -> add_expr bv e
  | Pcf_attribute _ | Pcf_extension _ -> ()

and add_class_declaration bv decl =
  add_class_expr bv decl.pci_expr

end
module Ocaml_extract : sig 
#1 "ocaml_extract.mli"
module C = Stack
val read_parse_and_extract :
    'a -> (Depend.StringSet.t -> 'a -> 'b) -> Depend.StringSet.t
type file_kind = ML | MLI
val files :
    (Depend.StringSet.elt * file_kind * Depend.StringSet.t) list ref
val ml_file_dependencies : string * Parsetree.structure -> unit
val mli_file_dependencies :
    Depend.StringSet.elt * Parsetree.signature -> unit
val normalize : string -> string
val merge :
    (string * file_kind * Depend.StringSet.t) list ->
      (string, Depend.StringSet.t) Hashtbl.t
val sort_files_by_dependencies :
    (string * file_kind * Depend.StringSet.t) list ->
      Depend.StringSet.elt C.t

val process : string list -> Parsetree.structure_item

val process_as_string : 
  string list ->  
  [`All of string * string * string * string * string 
  |`Ml of string *  string * string ] list 

end = struct
#1 "ocaml_extract.ml"
module C = Stack
let read_parse_and_extract ast extract_function =
  Depend.free_structure_names := Depend.StringSet.empty;
  (let bound_vars = Depend.StringSet.empty in
  List.iter
    (fun modname  ->
      Depend.open_module bound_vars (Longident.Lident modname))
    (!Clflags.open_modules);
  extract_function bound_vars ast;
  !Depend.free_structure_names)
type file_kind =
  | ML
  | MLI
let files = ref []
let ml_file_dependencies ((source_file : string),ast) =
  let extracted_deps =
    read_parse_and_extract ast Depend.add_implementation in
  files := ((source_file, ML, extracted_deps) :: (!files))
let mli_file_dependencies (source_file,ast) =
  let extracted_deps =
    read_parse_and_extract ast Depend.add_signature in
  files := ((source_file, MLI, extracted_deps) :: (!files))
let normalize file  =
  let modname = String.capitalize 
      (Filename.chop_extension @@ Filename.basename file) in
  modname

let merge (files : (string * file_kind * Depend.StringSet.t) list ) =
  let tbl = Hashtbl.create 31 in 

  let domain = Depend.StringSet.of_list 
      (List.map (fun (x,_,_)-> normalize x) files) in
  let () = List.iter (fun  (file,file_kind,deps) ->
    let modname = String.capitalize 
        (Filename.chop_extension @@ Filename.basename file) in
    match Hashtbl.find tbl modname with 
    | new_deps -> Hashtbl.replace tbl modname 
          (Depend.StringSet.inter domain (Depend.StringSet.union deps new_deps))
    | exception Not_found -> 
        Hashtbl.add tbl  modname (Depend.StringSet.inter deps domain)
                     ) files  in tbl


let sort_files_by_dependencies 
    (files : (string * file_kind * Depend.StringSet.t) list)
    =
  let h : (string, Depend.StringSet.t) Hashtbl.t = merge files in
  let () = 
    begin
      (* prerr_endline "dumping dependency table"; *)
      (* Hashtbl.iter (fun key _ -> prerr_endline key) h ; *)
      (* prerr_endline "dumping dependency finished"; *)
    end in
  let worklist = Stack.create () in
  let ()= 
    Hashtbl.iter (fun key _     -> Stack.push key worklist ) h in
  let result = C.create () in
  let visited = Hashtbl.create 31 in

  while not @@ Stack.is_empty worklist do 
    (* let () =  *)
    (*   prerr_endline "stack ..."; *)
    (*   Stack.iter (fun x -> prerr_string x ; prerr_string" ") worklist ; *)
    (*   prerr_endline "stack ...end" *)
    (* in *)
    let current = Stack.top worklist  in 
    if Hashtbl.mem visited current then
      ignore @@ Stack.pop worklist 
    else 
      match Depend.StringSet.elements (Hashtbl.find h current) with 
      | depends -> 
          let really_depends = 
            List.filter (fun x ->  (Hashtbl.mem h x && (not (Hashtbl.mem visited x ))))
              depends in
          begin match really_depends with 
          |[] -> begin
              let v = Stack.pop worklist in
              Hashtbl.add visited  v () ;
              (* prerr_endline (Printf.sprintf "poping %s" v); *)
              C.push current result 
          end
          | _ -> 
              List.iter  (fun x -> Stack.push x worklist) really_depends
          end
      | exception Not_found ->  assert false 
            (* prerr_endline current; *)
            (* Hashtbl.iter (fun k _ -> prerr_endline k) h ; *)
            (* failwith current *)
  done;
  result
;;

type 'a code_info = 
  {
    name : string ;
    content : string;
    ast : 'a
  }

type ml_info = Parsetree.structure code_info

type mli_info = Parsetree.signature code_info

(** on 32 bit , there are 16M limitation *)
let load_file f =
  let ic = open_in f in
  let n = in_channel_length ic in
  let s = Bytes.create n in
  really_input ic s 0 n;
  close_in ic;
  Bytes.unsafe_to_string s

let _loc = Location.none 

let assemble  ast_tbl  stack = 
  let structure_items = ref [] in
  let visited = Hashtbl.create 31 in
  Stack.iter
    (fun base  ->
      match Hashtbl.find visited base with 
      | exception Not_found ->
          Hashtbl.add visited base ();
          begin match Hashtbl.find_all ast_tbl base with
            | `ml {ast = structure;  _}:: `mli { ast = signature; _}::[]
            | `mli { ast = signature; _} ::`ml { ast = structure; _}::[] ->
              let v: Parsetree.structure_item =
                {
                  Parsetree.pstr_loc = _loc;
                  pstr_desc =
                    (Pstr_module
                       {
                         pmb_name =
                           { txt = (String.capitalize base); loc = _loc
                           };
                         pmb_expr =
                           {
                             pmod_desc =
                               (Pmod_constraint
                                  ({
                                    pmod_desc =
                                      (Pmod_structure structure);
                                    pmod_loc = _loc;
                                    pmod_attributes = []
                                  },
                                    ({
                                      pmty_desc =
                                        (Pmty_signature signature);
                                      pmty_loc = _loc;
                                      pmty_attributes = []
                                    } : Parsetree.module_type)));
                             pmod_loc = _loc;
                             pmod_attributes = []
                           };
                         pmb_attributes = [];
                         pmb_loc = _loc
                       })
                } in
              structure_items := (v :: (!structure_items))
            | `ml {ast = structure; _}::[] ->
              let v: Parsetree.structure_item =
                {
                  Parsetree.pstr_loc = _loc;
                  pstr_desc =
                    (Pstr_module
                       {
                         pmb_name =
                           { txt = (String.capitalize base); loc = _loc
                           };
                         pmb_expr =
                           {
                             pmod_desc = (Pmod_structure structure);
                             pmod_loc = _loc;
                             pmod_attributes = []
                           };
                         pmb_attributes = [];
                         pmb_loc = _loc
                       })
                } in
              structure_items := (v :: (!structure_items))

            | _ -> assert false
          end
      | _ -> () 
    ) stack;
  {
    Parsetree.pstr_loc = _loc;
    pstr_desc =
      (Pstr_include
         {
           pincl_mod =
             {
               pmod_desc = (Pmod_structure ( !structure_items));
               pmod_loc = _loc;
               pmod_attributes = []
             };
           pincl_loc = _loc;
           pincl_attributes = []
         })
  }


let assemble_as_string  ast_tbl  stack = 
  let structure_items = ref [] in
  let visited = Hashtbl.create 31 in
  Stack.iter
    (fun base  ->
      match Hashtbl.find visited base with 
      | exception Not_found ->
          Hashtbl.add visited base ();
          begin match Hashtbl.find_all ast_tbl base with
            | [`ml {content = ml_content; name = ml_name};
              `mli { content = mli_content; name = mli_name}]
            | [`mli {content = mli_content; name = mli_name} ;
              `ml { content = ml_content; name = ml_name}] ->
              structure_items := 
                `All (base, ml_content,ml_name, mli_content, mli_name)
                :: !structure_items
            | `ml {content = ml_content; name}::[] ->
              structure_items := 
                `Ml (base, ml_content, name) :: !structure_items
            | _ -> assert false
          end
      | _ -> () 
    ) stack;
  !structure_items


let prepare arg_files = 
  let ast_tbl = Hashtbl.create 31 in
  let files_set = Depend.StringSet.of_list @@ arg_files in
  let () = files_set |> Depend.StringSet.iter (fun name ->
    let content = load_file name in  
    let base = normalize name in
    if Filename.check_suffix name ".ml"
    then
      let ast = Parse.implementation (Lexing.from_string content) in
      (Hashtbl.add ast_tbl base (`ml {ast; name; content });
       ml_file_dependencies (name, ast))
    else
      if Filename.check_suffix name ".mli"
      then
        (if Depend.StringSet.mem  
            (Filename.chop_extension name ^ ".ml") files_set then
          match Parse.interface (Lexing.from_string content) with 
          | ast -> 
              Hashtbl.add ast_tbl base (`mli {ast; name; content});
              mli_file_dependencies (name, ast)
          | exception _ -> failwith (Printf.sprintf "failed parsing %s" name)
        else
          begin match Parse.interface (Lexing.from_string content) with 
          | ast -> 
              (* prerr_endline name; *)
              Hashtbl.add ast_tbl base (`mli {ast ;  name; content});
              mli_file_dependencies (name, ast);
              begin match  
                  Parse.implementation  
                    (Lexing.from_string content) 
                with
              | ast ->
                  Hashtbl.add ast_tbl base (`ml { ast;  name; content});
                  ml_file_dependencies 
                    (name, ast) (* Fake*)
              | exception _ -> failwith (Printf.sprintf "failed parsing %s as ml" name) 
              end
          | exception _  -> 
              failwith (Printf.sprintf "failed parsing %s" name) 
          end
        )
      else assert false) in
  ast_tbl, sort_files_by_dependencies (!files)

let process arg_files  : Parsetree.structure_item =
  let ast_tbl, stack_files = prepare arg_files in
  assemble ast_tbl stack_files

let process_as_string  arg_files  = 
  let ast_tbl, stack_files = prepare arg_files in
  assemble_as_string ast_tbl stack_files


(**
   known issues:
   we take precedence of ml seriously, however, there is a case 
   1. module a does not depend on b 
   while interface a does depend on b 
   in this case, we put a before b which will cause a compilation error 
   (this does happens when user use polymorphic variants in the interface while does not refer module b in the implementation, while the interface does refer module b)

   2. if we only take interface seriously, first the current worklist algorithm does not provide 
   [same level ] information, second the dependency captured by interfaces are very limited.
   3. The solution would be combine the dependency of interfaces and implementations altogether, 
   we will get rid of some valid use cases, but it's worth 
   
 *)
(* local variables: *)
(* compile-command: "ocamlopt.opt -inline 1000 -I +compiler-libs -c depend.ml ocaml_extract.mli ocaml_extract.ml " *)
(* end: *)

end
module Line_process : sig 
#1 "line_process.mli"
(** Given a filename return a list of modules *)
val read_lines : string -> string list 

end = struct
#1 "line_process.ml"

(* let lexer = Genlex.make_lexer [] (\* poor man *\) *)

(* let rec to_list acc stream =  *)
(*   match Stream.next stream with  *)
(*   | exception _ -> List.rev acc  *)
(*   | v -> to_list (v::acc) stream  *)
 

let rev_lines_of_file file = 
  let chan = open_in file in
  let rec loop acc = 
    match input_line chan with
    | line -> loop (line :: acc)
    | exception End_of_file -> close_in chan ; acc in
  loop []


let rec filter_map (f: 'a -> 'b option) xs = 
  match xs with 
  | [] -> []
  | y :: ys -> 
      begin match f y with 
      | None -> filter_map f ys
      | Some z -> z :: filter_map f ys
      end

let trim s = 
  let i = ref 0  in
  let j = String.length s in 
  while !i < j &&  let u = s.[!i] in u = '\t' || u = '\n' || u = ' ' do 
    incr i;
  done;
  let k = ref (j - 1)  in 
  while !k >= !i && let u = s.[!k] in u = '\t' || u = '\n' || u = ' ' do 
    decr k ;
  done;
  String.sub s !i (!k - !i + 1)


(* let process_line line =  *)
(*   match to_list [] (lexer (Stream.of_string line)) with *)
(*   | Ident "#" :: _ -> None *)
(*   | (Ident v|Kwd v) :: _ -> Some v  *)
(*   | (Int _ | Float _ | Char _ | String _ )  :: _ ->  *)
(*       assert false  *)
(*   | [] -> None  *)

let process_line line = 
  let line = trim line in 
  let len = String.length line in 
  if len = 0 then None
  else 
    match line.[0] with 
    | '#' -> None
    | _ -> Some line 

let (@>) v acc = 
  if Sys.file_exists v then 
    v :: acc 
  else acc 

let read_lines file = 
  file 
  |> rev_lines_of_file 
  |> List.fold_left (fun acc f -> 
      match process_line f with 
      | None -> acc 
      | Some f -> 
         (f ^ ".mli") @> (f ^ ".ml") @> acc
    ) []

end
module Ocaml_pack_main : sig 
#1 "ocaml_pack_main.mli"

end = struct
#1 "ocaml_pack_main.ml"

let make_comment _loc str =           
      {
        Parsetree.pstr_loc = _loc;
        pstr_desc =
          (Pstr_attribute
             (({ loc = _loc; txt =  "ocaml.doc"},
               (PStr
                  [{
                    Parsetree.pstr_loc = _loc;
                    pstr_desc =
                      (Pstr_eval
                         ({
                           pexp_loc = _loc;
                           pexp_desc =
                             (Pexp_constant (** Copy right header *)
                                (Const_string (str, None)));
                           pexp_attributes = []
                         }, []))
                  }])) : Parsetree.attribute))
      }


let _ = 
  let _loc = Location.none in
  let argv = Sys.argv in
  let files = 
    if Array.length argv = 2 && Filename.check_suffix  argv.(1) "mllib" then 
      Line_process.read_lines argv.(1)
    else 
      Array.to_list
        (Array.sub Sys.argv 1 (Array.length Sys.argv - 1)) 
  in 
  let tasks = Ocaml_extract.process_as_string files in 
  let emit name = 
    output_string stdout "#1 \"";
    output_string stdout name ;
    output_string stdout "\"\n" 
  in
  tasks |> List.iter (fun t ->
      match t with
      | `All (base, ml_content,ml_name, mli_content, mli_name) -> 
        let base = String.capitalize base in 
        output_string stdout "module ";
        output_string stdout base ; 
        output_string stdout " : sig \n";

        emit mli_name ;
        output_string stdout mli_content;

        output_string stdout "\nend = struct\n";
        emit ml_name ;
        output_string stdout ml_content;
        output_string stdout "\nend\n"

      | `Ml (base, ml_content, ml_name) -> 
        let base = String.capitalize base in 
        output_string stdout "module \n";
        output_string stdout base ; 
        output_string stdout "\n= struct\n";

        emit ml_name;
        output_string stdout ml_content;

        output_string stdout "\nend\n"

    )

(* local variables: *)
(* compile-command: "ocamlbuild -no-hygiene -cflags -annot -use-ocamlfind -pkg compiler-libs.common ocaml_pack_main.byte " *)
(* end: *)

end
