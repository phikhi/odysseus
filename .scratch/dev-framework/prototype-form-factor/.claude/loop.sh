#!/usr/bin/env bash
# PROTOTYPE — la ralph loop, assemblée à partir des décisions verrouillées. JETABLE (stubs).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
source .claude/ralph.config.sh
source .claude/lib/select.sh   # [04]  frontier_min_nn
source .claude/lib/budget.sh   # [07]  budget_check / budget_pause / budget_classify
source .claude/lib/gate.sh     # [08]  run_gate (tests+typecheck+review // )
source .claude/lib/state.sh    # [04]  mark_resolved / escalate / append_runlog / acquire_lock

acquire_lock "$FEATURE"                                   # [04] verrou de run grossier
kill_flag=0; trap 'kill_flag=1' SIGINT SIGTERM            # [06/D2] kill gracieux
iter=0; sterile=0

while :; do
  (( kill_flag ))        && { echo "exit: arrêt humain"; exit 0; }          # [06]
  (( iter >= ITER_CAP )) && { echo "exit: cap itérations"; exit 3; }        # [06/D3]
  (( sterile >= STERILE_K )) && { echo "exit: run stérile (ALERTE)"; exit 4; } # [06/D3]

  ticket="$(frontier_min_nn "$FEATURE")"                  # [04] scan gratuit, min NN
  if [ -z "$ticket" ]; then                               # [06/D2] one-shot
    if frontier_has_ready_for_human "$FEATURE"; then echo "exit: bloqué-humain"; exit 2
    else echo "exit: tout résolu"; exit 0; fi
  fi

  budget_check "$THRESH_5H" "$THRESH_WEEK" || { budget_pause "$WEEKLY_RESUME" || exit 5; continue; } # [07] proactif

  PRE="$(git rev-parse HEAD)"                             # [08/D3] snapshot rollback
  out="$(cat ".scratch/$FEATURE/issues/$ticket" | \
        claude -p "$(prompt_template "$ticket")" \        # [05] ticket via stdin + pointeurs + /implement
          --output-format stream-json --model "$MODEL" \  # [01/03] stream-json = monitoring live
          --dangerously-skip-permissions \                # [06/D1] bypass (sandbox !)
          --append-system-prompt "$ROLE" \
        | tee >(monitor_150k "$SOFT_LIMIT_TOKENS"))" || true   # [03] SIGTERM au franchissement

  if ! is_success "$out"; then                            # is_error / exit non-zéro
    if budget_classify; then budget_pause "$WEEKLY_RESUME" || exit 5; git reset --hard "$PRE"; continue; fi # [07] budget ≠ échec
    if too_big "$out"; then autonomous_reslice "$ticket" || escalate "$ticket" "AC menacées"; git reset --hard "$PRE"; git clean -fd; (( iter++ )); continue; fi # [08] re-slice auto (révise [03])
    # sinon: échec réel -> retry N fresh puis escalade [08]
    failures="$(bump_failures "$ticket")"
    (( failures > RETRY_N )) && { branch_failed "$ticket"; escalate "$ticket" "échec gate x$failures"; }
    git reset --hard "$PRE"; git clean -fd; (( sterile++ )); (( iter++ )); continue   # [08/D3] rollback propre
  fi

  if run_gate "$TEST_CMD" "$TYPECHECK_CMD" "$ticket"; then   # [08] tests+typecheck+/code-review EN //
    mark_resolved "$ticket"; sterile=0                        # [04] temp+mv après gate
  else
    failures="$(bump_failures "$ticket")"
    (( failures > RETRY_N )) && { branch_failed "$ticket"; escalate "$ticket" "gate rouge x$failures"; }
    git reset --hard "$PRE"; git clean -fd; (( sterile++ ))   # [08/D3] rollback
  fi

  append_runlog "$ticket" "$out"                           # [04/06/07] tâche,is_error,coût,tours,utilization
  (( iter++ ))
  maybe_human_checkpoint "$HUMAN_CHECKPOINT_EVERY"         # [06/D3] off par défaut
done
