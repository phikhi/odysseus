# Spec — Demo feature

Status: ready-for-agent

Fixture spec for the harness. The terminal value gate replays the user flow
below on real assets, so the feature needs one that is stated end to end.

## Problem Statement

The demo project cannot show a marker to its user.

## Solution

Write the markers, then print them.

## User Flow

1. The user runs `make demo`.
2. The output lists every marker under `src/`.
3. The user sees `alpha` and `beta`.

## Testing Decisions

- Objective checks are stubbed through `stub-cmd`; the flow above is what the
  playthrough asserts.
