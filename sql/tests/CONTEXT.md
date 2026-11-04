# sql/tests - data tests that stop a bad run

One job: catch a wrong number before it is published.

## Inputs
- Working (this run): the tables built by `../models/`
- Reference (every run): `../../_shared/definitions.md`

## Process
1. Each file is one query that returns the rows that break a rule; zero rows is a pass.
2. Name it `test_<what must hold>.sql` and start it with a comment saying the rule.
3. `run_data_tests()` runs them all; any failure stops `run_pipeline.R` before rendering.

## Outputs
- Nothing on pass; the failing test name and rows in the run log on fail.

## Check
Break the rule on purpose once (e.g. change `<` to `<=` in a leakage guard) and confirm the test fails.
