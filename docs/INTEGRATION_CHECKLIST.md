# Member C integration checklist

- [ ] Generate Python vectors; verify the LFSR and fixed-point path-ID software tests.
- [ ] Simulate `tb_lfsr.v` and compare state/sample outputs.
- [ ] Simulate `tb_sec_path_id.v`; verify 128 coefficients match the generated Python reference.
- [ ] Simulate power-meter and dB benches.
- [ ] Connect `sec_path_id.shat_addr` / `shat_data` directly to Member B's `fxlms` ports.
- [ ] Confirm `probe_valid` and `measured_in` refer to the same sample index.
- [ ] Confirm system clock gives at least 256 clocks per sample tick; watch `sample_overrun`.
- [ ] Read `sample_count`, `last_id_cycles`, `coeff_overflow`, and `sample_overrun` in ILA.
- [ ] On hardware, collect ANC-off and ANC-on 1024-sample error-microphone windows; compare dBFS and attenuation.
- [ ] Check physical path latency fits M=128; otherwise raise M in both Member C and Member B designs.
