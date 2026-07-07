# Reference fixtures — provenance

`stitch.dst` and `color_change.dst` are byte-exact copies from the Catrobat
**Catty** repository (AGPL-3.0), path `src/CattyTests/Resources/EmbroideryReference/`,
last touched there in commit `55c704a789e9d50d486e00d8191fea5711ac8155`
("CATTY-573 \"Set thread color to __\" Brick", 2023-01-21).
Source: https://github.com/Catrobat/Catty

SHA-256:

```
a26081dc8c5638f5953c7ce48aac4ef3b7e46644464cad261c0840d0799d699e  stitch.dst
bf8c153ae0ded6cac5dbbbf0320970587ead81ede675a71d32b692d1dfed1dbc  color_change.dst
```

They are Catty-generated "self-golden" files: Catty's own DST writer produced
them, so they inherit any Catty writer bugs. ADR-012 in `docs/DECISIONS.md`
pins which byte-level semantics are authoritative (Catroid wins) and lists the
known Catty bugs; golden tests in US-104/US-106 must be read against that.
US-101 requires verifying that both files render correctly in a named external
embroidery viewer before US-104/US-106 build golden tests on them; record the
viewer name and result here once done.
