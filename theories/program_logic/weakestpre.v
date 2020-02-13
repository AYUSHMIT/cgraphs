From iris.proofmode Require Import base tactics classes.
From iris.base_logic.lib Require Export fancy_updates.
From diris.program_logic Require Export language.
From diris.program_logic Require Export ectx_language.

(* FIXME: If we import iris.bi.weakestpre earlier texan triples do not
   get pretty-printed correctly. *)
From diris.bi Require Export weakestpre.
Set Default Proof Using "Type".
Import uPred.

Class irisG (Λ : ectxLanguage) (Σ : gFunctors) := IrisG {
  iris_invG :> invG Σ;

  (** The state interpretation is an invariant that should hold in between each
  step of reduction. Here [Λstate] is the global state, [list Λobservation] are
  the remaining observations, and [nat] is the number of forked-off threads
  (not the total number of threads, which is one higher because there is always
  a main thread). *) 
  state_interp : state Λ → list (observation Λ) → list (expr Λ) → iProp Σ;

  (** A fixed postcondition for any forked-off thread. For most languages, e.g.
  heap_lang, this will simply be [True]. However, it is useful if one wants to
  keep track of resources precisely, as in e.g. Iron. *)
  fork_post : nat → val Λ → iProp Σ;
}.
Global Opaque iris_invG.


Definition wp_pre `{!irisG Λ Σ} (s : stuckness)
    (wp : nat -d> coPset -d> expr Λ -d> (val Λ -d> iPropO Σ) -d> iPropO Σ) :
    nat -d> coPset -d> expr Λ -d> (val Λ -d> iPropO Σ) -d> iPropO Σ := λ tid E e1 Φ,
  match to_val e1 with
  | Some v => |={E}=> Φ v
  | None => ∀ σ1 κ κs es K,
     ⌜ es !! tid = Some (fill K e1) ⌝ -∗
     state_interp σ1 (κ ++ κs) es ={E,∅}=∗
       ⌜if s is NotStuck then reducible e1 σ1 ∨ waiting e1 σ1 else True⌝ ∗
       ∀ e2 σ2 efs, ⌜prim_step e1 σ1 κ e2 σ2 efs⌝ ={∅,∅,E}▷=∗
         state_interp σ2 κs ((<[tid := fill K e2]> es) ++ efs) ∗
         wp tid E e2 Φ ∗
         [∗ list] i ↦ ef ∈ efs, wp (length es + i) ⊤ ef (fork_post (length es + i))
  end%I.

Local Instance wp_pre_contractive `{!irisG Λ Σ} s : Contractive (wp_pre s).
Proof.
  rewrite /wp_pre=> n wp wp' Hwp tid E e1 Φ.
  repeat (f_contractive || f_equiv); apply Hwp.
Qed.

Definition wp_def `{!irisG Λ Σ} (si : stuckness * nat) :
  coPset → expr Λ → (val Λ → iProp Σ) → iProp Σ := fixpoint (wp_pre si.1) si.2.
Definition wp_aux `{!irisG Λ Σ} : seal (@wp_def Λ Σ _). by eexists. Qed.
Instance wp' `{!irisG Λ Σ} : Wp Λ (iProp Σ) (stuckness * nat) := wp_aux.(unseal).
Definition wp_eq `{!irisG Λ Σ} : wp = @wp_def Λ Σ _ := wp_aux.(seal_eq).

Section wp.
Context `{!irisG Λ Σ}.
Implicit Types s : stuckness.
Implicit Types P : iProp Σ.
Implicit Types Φ : val Λ → iProp Σ.
Implicit Types v : val Λ.
Implicit Types e : expr Λ.

(* Weakest pre *)
Lemma wp_unfold s i E e Φ :
  WP e @ (s,i); E {{ Φ }} ⊣⊢ wp_pre s (fun k => wp (PROP:=iProp Σ)  (s,k)) i E e Φ.
Proof. rewrite wp_eq. unfold wp_def. simpl. 
  rewrite (_ : (λ k : nat, fixpoint (wp_pre s) k) = fixpoint (wp_pre s)); last done.
  apply (fixpoint_unfold (wp_pre s)).
Qed.

Global Instance wp_ne s i E e n :
  Proper (pointwise_relation _ (dist n) ==> dist n) (wp (PROP:=iProp Σ) (s,i) E e).
Proof.
  revert e. induction (lt_wf n) as [n _ IH]=> e Φ Ψ HΦ.
  rewrite !wp_unfold /wp_pre.
  (* FIXME: figure out a way to properly automate this proof *)
  (* FIXME: reflexivity, as being called many times by f_equiv and f_contractive
  is very slow here *)
  do 27 (f_contractive || f_equiv). apply IH; first lia.
  intros v. eapply dist_le; eauto with lia.
Qed.
Global Instance wp_proper s i E e :
  Proper (pointwise_relation _ (≡) ==> (≡)) (wp (PROP:=iProp Σ) (s,i) E e).
Proof.
  by intros Φ Φ' ?; apply equiv_dist=>n; apply wp_ne=>v; apply equiv_dist.
Qed.
Global Instance wp_contractive s i E e n :
  TCEq (to_val e) None →
  Proper (pointwise_relation _ (dist_later n) ==> dist n) (wp (PROP:=iProp Σ) (s,i) E e).
Proof.
  intros He Φ Ψ HΦ. rewrite !wp_unfold /wp_pre He.
  by repeat (f_contractive || f_equiv).
Qed.

Lemma wp_value' s i E Φ v : Φ v ⊢ WP of_val v @ (s,i); E {{ Φ }}.
Proof. iIntros "HΦ". rewrite wp_unfold /wp_pre to_of_val. auto. Qed.
Lemma wp_value_inv' s i E Φ v : WP of_val v @ (s,i); E {{ Φ }} ={E}=∗ Φ v.
Proof. by rewrite wp_unfold /wp_pre to_of_val. Qed.

Lemma wp_strong_mono s1 s2 i E1 E2 e Φ Ψ :
  s1 ⊑ s2 → E1 ⊆ E2 →
  WP e @ (s1,i); E1 {{ Φ }} -∗ (∀ v, Φ v ={E2}=∗ Ψ v) -∗ WP e @ (s2,i); E2 {{ Ψ }}.
Proof.
  iIntros (? HE) "H HΦ". iLöb as "IH" forall (e i E1 E2 HE Φ Ψ).
  rewrite !wp_unfold /wp_pre.
  destruct (to_val e) as [v|] eqn:?.
  { iApply ("HΦ" with "[> -]"). by iApply (fupd_mask_mono E1 _). }
  iIntros (σ1 κ κs es K ?) "Hσ". iMod (fupd_intro_mask' E2 E1) as "Hclose"; first done.
  iMod ("H" with "[//] [$]") as "[% H]".
  iModIntro. iSplit; [by destruct s1, s2|]. iIntros (e2 σ2 efs Hstep).
  iMod ("H" with "[//]") as "H". iIntros "!> !>".
  iMod "H" as "(Hσ & H & Hefs)".
  iMod "Hclose" as "_". iModIntro. iFrame "Hσ". iSplitR "Hefs".
  - iApply ("IH" with "[//] H HΦ").
  - iApply (big_sepL_impl with "Hefs"); iIntros "!#" (k ef _).
    iIntros "H". iApply ("IH" with "[] H"); auto.
Qed.

Lemma fupd_wp s i E e Φ : (|={E}=> WP e @ (s,i); E {{ Φ }}) ⊢ WP e @ (s,i); E {{ Φ }}.
Proof.
  rewrite wp_unfold /wp_pre. iIntros "H". destruct (to_val e) as [v|] eqn:?.
  { by iMod "H". }
  iIntros (σ1 κ κs es K ?) "Hσ1". iMod "H". by iApply "H".
Qed.
Lemma wp_fupd s i E e Φ : WP e @ (s,i); E {{ v, |={E}=> Φ v }} ⊢ WP e @ (s,i); E {{ Φ }}.
Proof. iIntros "H". iApply (wp_strong_mono s s i E with "H"); auto. Qed.

Lemma wp_atomic s i E1 E2 e Φ `{!Atomic (stuckness_to_atomicity s) e} :
  (|={E1,E2}=> WP e @ (s,i); E2 {{ v, |={E2,E1}=> Φ v }}) ⊢ WP e @ (s,i); E1 {{ Φ }}.
Proof.
  iIntros "H". rewrite !wp_unfold /wp_pre.
  destruct (to_val e) as [v|] eqn:He.
  { by iDestruct "H" as ">>> $". }
  iIntros (σ1 κ κs es K ?) "Hσ". iMod "H". iMod ("H" $! σ1 with "[//] Hσ") as "[$ H]".
  iModIntro. iIntros (e2 σ2 efs Hstep).
  iMod ("H" with "[//]") as "H". iIntros "!>!>".
  iMod "H" as "(Hσ & H & Hefs)". destruct s.
  - rewrite !wp_unfold /wp_pre. destruct (to_val e2) as [v2|] eqn:He2.
    + iDestruct "H" as ">> $". by iFrame.
    + iMod ("H" $! _ [] with "[%] [$]") as "[H _]". 
      { apply lookup_app_l_Some. apply list_lookup_insert. by eapply lookup_lt_Some. }
      iDestruct "H" as %[H|H]. 
      * destruct H as (? & ? & ? & ? & ?). apply atomic in Hstep as [? ?].
        edestruct H0. eauto.
      * apply atomic in Hstep as [? ?]. done.
  - destruct (atomic _ _ _ _ _ Hstep) as [v <-%of_to_val].
    iMod (wp_value_inv' with "H") as ">H".
    iModIntro. iFrame "Hσ Hefs". by iApply wp_value'.
Qed.

Lemma wp_step_fupd s i E1 E2 e P Φ :
  to_val e = None → E2 ⊆ E1 →
  (|={E1,E2}▷=> P) -∗ WP e @ (s,i); E2 {{ v, P ={E1}=∗ Φ v }} -∗ WP e @ (s,i); E1 {{ Φ }}.
Proof.
  rewrite !wp_unfold /wp_pre. iIntros (-> ?) "HR H".
  iIntros (σ1 κ κs es K ?) "Hσ". iMod "HR". iMod ("H" with "[//] [$]") as "[$ H]".
  iIntros "!>" (e2 σ2 efs Hstep). iMod ("H" $! e2 σ2 efs with "[% //]") as "H".
  iIntros "!>!>". iMod "H" as "(Hσ & H & Hefs)".
  iMod "HR". iModIntro. iFrame "Hσ Hefs".
  iApply (wp_strong_mono s s i E2 with "H"); [done..|].
  iIntros (v) "H". by iApply "H".
Qed.

Lemma wp_bind K s i E e Φ :
  WP e @ (s,i); E {{ v, WP fill K (of_val v) @ (s,i); E {{ Φ }} }} ⊢ WP fill K e @ (s,i); E {{ Φ }}.
Proof.
  iIntros "H". iLöb as "IH" forall (E e i Φ). rewrite wp_unfold /wp_pre.
  destruct (to_val e) as [v|] eqn:He.
  { apply of_to_val in He as <-. by iApply fupd_wp. }
  rewrite wp_unfold /wp_pre fill_not_val //.
  iIntros (σ1 κ κs es K' ?) "Hσ". rewrite fill_comp in a. iMod ("H" with "[//] [$]") as "[% H]".
  iModIntro; iSplit.
  { iPureIntro. destruct s; last done. destruct H.
    - left. eauto using fill_reducible.
    - right. apply waiting_fill. exact H. }
  iIntros (e2 σ2 efs Hstep).
  destruct (fill_step_inv e σ1 κ e2 σ2 efs) as (e2'&->&?); [done..|].
  iMod ("H" $! e2' σ2 efs with "[//]") as "H". iIntros "!>!>".
  iMod "H" as "(Hσ & H & Hefs)".
  iModIntro. rewrite fill_comp. iFrame "Hσ Hefs". by iApply "IH".
Qed.

(* No longer holds!  *)
(* Lemma wp_bind_inv K `{!LanguageCtx K} s E e Φ :
  WP K e @ s; E {{ Φ }} ⊢ WP e @ s; E {{ v, WP K (of_val v) @ s; E {{ Φ }} }}.
Proof.
  iIntros "H". iLöb as "IH" forall (E e Φ). rewrite !wp_unfold /wp_pre.
  destruct (to_val e) as [v|] eqn:He.
  { apply of_to_val in He as <-. by rewrite !wp_unfold /wp_pre. }
  rewrite fill_not_val //.
  iIntros (σ1 κ κs n) "Hσ". iMod ("H" with "[$]") as "[% H]". iModIntro; iSplit.
  { destruct s; naive_solver eauto using reducible_fill, waiting_fill, fill_waiting. }
  iIntros (e2 σ2 efs Hstep).
  iMod ("H" $! (K e2) σ2 efs with "[]") as "H"; [by eauto using fill_step|].
  iIntros "!>!>". iMod "H" as "(Hσ & H & Hefs)".
  iModIntro. iFrame "Hσ Hefs". by iApply "IH".
Qed. *)

(** * Derived rules *)
Lemma wp_mono s i E e Φ Ψ : (∀ v, Φ v ⊢ Ψ v) → WP e @ (s,i); E {{ Φ }} ⊢ WP e @ (s,i); E {{ Ψ }}.
Proof.
  iIntros (HΦ) "H"; iApply (wp_strong_mono with "H"); auto.
  iIntros (v) "?". by iApply HΦ.
Qed.
Lemma wp_stuck_mono s1 s2 i E e Φ :
  s1 ⊑ s2 → WP e @ (s1,i); E {{ Φ }} ⊢ WP e @ (s2,i); E {{ Φ }}.
Proof. iIntros (?) "H". iApply (wp_strong_mono with "H"); auto. Qed.

(* Jules TODO *)
Lemma wp_stuck_weaken s i E e Φ :
  WP e @ (s,i); E {{ Φ }} ⊢ WP e @ (MaybeStuck,i); E {{ Φ }}.
Proof. apply wp_stuck_mono. by destruct s. Qed.
Lemma wp_mask_mono s i E1 E2 e Φ : E1 ⊆ E2 → WP e @ (s,i); E1 {{ Φ }} ⊢ WP e @ (s,i); E2 {{ Φ }}.
Proof. iIntros (?) "H"; iApply (wp_strong_mono with "H"); auto. Qed.
Global Instance wp_mono' s i E e :
  Proper (pointwise_relation _ (⊢) ==> (⊢)) (wp (PROP:=iProp Σ) (s,i) E e).
Proof. by intros Φ Φ' ?; apply wp_mono. Qed.
Global Instance wp_flip_mono' s i E e :
  Proper (pointwise_relation _ (flip (⊢)) ==> (flip (⊢))) (wp (PROP:=iProp Σ) (s,i) E e).
Proof. by intros Φ Φ' ?; apply wp_mono. Qed.

Lemma wp_value s i E Φ e v : IntoVal e v → Φ v ⊢ WP e @ (s,i); E {{ Φ }}.
Proof. intros <-. by apply wp_value'. Qed.
Lemma wp_value_fupd' s i E Φ v : (|={E}=> Φ v) ⊢ WP of_val v @ (s,i); E {{ Φ }}.
Proof. intros. by rewrite -wp_fupd -wp_value'. Qed.
Lemma wp_value_fupd s i E Φ e v `{!IntoVal e v} :
  (|={E}=> Φ v) ⊢ WP e @ (s,i); E {{ Φ }}.
Proof. intros. rewrite -wp_fupd -wp_value //. Qed.
Lemma wp_value_inv s i E Φ e v : IntoVal e v → WP e @ (s,i); E {{ Φ }} ={E}=∗ Φ v.
Proof. intros <-. by apply wp_value_inv'. Qed.

Lemma wp_frame_l s i E e Φ R : R ∗ WP e @ (s,i); E {{ Φ }} ⊢ WP e @ (s,i); E {{ v, R ∗ Φ v }}.
Proof. iIntros "[? H]". iApply (wp_strong_mono with "H"); auto with iFrame. Qed.
Lemma wp_frame_r s i E e Φ R : WP e @ (s,i); E {{ Φ }} ∗ R ⊢ WP e @ (s,i); E {{ v, Φ v ∗ R }}.
Proof. iIntros "[H ?]". iApply (wp_strong_mono with "H"); auto with iFrame. Qed.

Lemma wp_frame_step_l s i E1 E2 e Φ R :
  to_val e = None → E2 ⊆ E1 →
  (|={E1,E2}▷=> R) ∗ WP e @ (s,i); E2 {{ Φ }} ⊢ WP e @ (s,i); E1 {{ v, R ∗ Φ v }}.
Proof.
  iIntros (??) "[Hu Hwp]". iApply (wp_step_fupd with "Hu"); try done.
  iApply (wp_mono with "Hwp"). by iIntros (?) "$$".
Qed.
Lemma wp_frame_step_r s i E1 E2 e Φ R :
  to_val e = None → E2 ⊆ E1 →
  WP e @ (s,i); E2 {{ Φ }} ∗ (|={E1,E2}▷=> R) ⊢ WP e @ (s,i); E1 {{ v, Φ v ∗ R }}.
Proof.
  rewrite [(WP _ @ _; _ {{ _ }} ∗ _)%I]comm; setoid_rewrite (comm _ _ R).
  apply wp_frame_step_l.
Qed.
Lemma wp_frame_step_l' s i E e Φ R :
  to_val e = None → ▷ R ∗ WP e @ (s,i); E {{ Φ }} ⊢ WP e @ (s,i); E {{ v, R ∗ Φ v }}.
Proof. iIntros (?) "[??]". iApply (wp_frame_step_l s i E E); try iFrame; eauto. Qed.
Lemma wp_frame_step_r' s i E e Φ R :
  to_val e = None → WP e @ (s,i); E {{ Φ }} ∗ ▷ R ⊢ WP e @ (s,i); E {{ v, Φ v ∗ R }}.
Proof. iIntros (?) "[??]". iApply (wp_frame_step_r s i E E); try iFrame; eauto. Qed.

Lemma wp_wand s i E e Φ Ψ :
  WP e @ (s,i); E {{ Φ }} -∗ (∀ v, Φ v -∗ Ψ v) -∗ WP e @ (s,i); E {{ Ψ }}.
Proof.
  iIntros "Hwp H". iApply (wp_strong_mono with "Hwp"); auto.
  iIntros (?) "?". by iApply "H".
Qed.
Lemma wp_wand_l s i E e Φ Ψ :
  (∀ v, Φ v -∗ Ψ v) ∗ WP e @ (s,i); E {{ Φ }} ⊢ WP e @ (s,i); E {{ Ψ }}.
Proof. iIntros "[H Hwp]". iApply (wp_wand with "Hwp H"). Qed.
Lemma wp_wand_r s i E e Φ Ψ :
  WP e @ (s,i); E {{ Φ }} ∗ (∀ v, Φ v -∗ Ψ v) ⊢ WP e @ (s,i); E {{ Ψ }}.
Proof. iIntros "[Hwp H]". iApply (wp_wand with "Hwp H"). Qed.
Lemma wp_frame_wand_l s i E e Q Φ :
  Q ∗ WP e @ (s,i); E {{ v, Q -∗ Φ v }} -∗ WP e @ (s,i); E {{ Φ }}.
Proof.
  iIntros "[HQ HWP]". iApply (wp_wand with "HWP").
  iIntros (v) "HΦ". by iApply "HΦ".
Qed.

End wp.

(** Proofmode class instances *)
Section proofmode_classes.
  Context `{!irisG Λ Σ}.
  Implicit Types P Q : iProp Σ.
  Implicit Types Φ : val Λ → iProp Σ.

  Global Instance frame_wp p s i E e R Φ Ψ :
    (∀ v, Frame p R (Φ v) (Ψ v)) →
    Frame p R (WP e @ (s,i); E {{ Φ }}) (WP e @ (s,i); E {{ Ψ }}).
  Proof. rewrite /Frame=> HR. rewrite wp_frame_l. apply wp_mono, HR. Qed.

  Global Instance is_except_0_wp s i E e Φ : IsExcept0 (WP e @ (s,i); E {{ Φ }}).
  Proof. by rewrite /IsExcept0 -{2}fupd_wp -except_0_fupd -fupd_intro. Qed.

  Global Instance elim_modal_bupd_wp p s i E e P Φ :
    ElimModal True p false (|==> P) P (WP e @ (s,i); E {{ Φ }}) (WP e @ (s,i); E {{ Φ }}).
  Proof.
    by rewrite /ElimModal intuitionistically_if_elim
      (bupd_fupd E) fupd_frame_r wand_elim_r fupd_wp.
  Qed.

  Global Instance elim_modal_fupd_wp p s i E e P Φ :
    ElimModal True p false (|={E}=> P) P (WP e @ (s,i); E {{ Φ }}) (WP e @ (s,i); E {{ Φ }}).
  Proof.
    by rewrite /ElimModal intuitionistically_if_elim
      fupd_frame_r wand_elim_r fupd_wp.
  Qed.

  Global Instance elim_modal_fupd_wp_atomic p s i E1 E2 e P Φ :
    Atomic (stuckness_to_atomicity s) e →
    ElimModal True p false (|={E1,E2}=> P) P
            (WP e @ (s,i); E1 {{ Φ }}) (WP e @ (s,i); E2 {{ v, |={E2,E1}=> Φ v }})%I.
  Proof.
    intros. by rewrite /ElimModal intuitionistically_if_elim
      fupd_frame_r wand_elim_r wp_atomic.
  Qed.

  Global Instance add_modal_fupd_wp s i E e P Φ :
    AddModal (|={E}=> P) P (WP e @ (s,i); E {{ Φ }}).
  Proof. by rewrite /AddModal fupd_frame_r wand_elim_r fupd_wp. Qed.

  Global Instance elim_acc_wp {X} E1 E2 α β γ e s i Φ :
    Atomic (stuckness_to_atomicity s) e →
    ElimAcc (X:=X) (fupd E1 E2) (fupd E2 E1)
            α β γ (WP e @ (s,i); E1 {{ Φ }})
            (λ x, WP e @ (s,i); E2 {{ v, |={E2}=> β x ∗ (γ x -∗? Φ v) }})%I.
  Proof.
    intros ?. rewrite /ElimAcc.
    iIntros "Hinner >Hacc". iDestruct "Hacc" as (x) "[Hα Hclose]".
    iApply (wp_wand with "(Hinner Hα)").
    iIntros (v) ">[Hβ HΦ]". iApply "HΦ". by iApply "Hclose".
  Qed.

  Global Instance elim_acc_wp_nonatomic {X} E α β γ e s i Φ :
    ElimAcc (X:=X) (fupd E E) (fupd E E)
            α β γ (WP e @ (s,i); E {{ Φ }})
            (λ x, WP e @ (s,i); E {{ v, |={E}=> β x ∗ (γ x -∗? Φ v) }})%I.
  Proof.
    rewrite /ElimAcc.
    iIntros "Hinner >Hacc". iDestruct "Hacc" as (x) "[Hα Hclose]".
    iApply wp_fupd.
    iApply (wp_wand with "(Hinner Hα)").
    iIntros (v) ">[Hβ HΦ]". iApply "HΦ". by iApply "Hclose".
  Qed.
End proofmode_classes.
