# compare/

Shared data for comparing our build with the original (`docs/compare.md`):

* `scripts/*.mwi` - input scripts (both sides play them)
* `probes/*.json` - probe sets: named fields, how each side provides them,
  how they are compared
* `button_verbs.json` - original buttons -> verbs per context
* `fixtures/` - parity fixtures checked by both pytest and GUT

Numbers and input events only: no ROM text, pixels or tile data.
