# Distillations: "Direct Observation Prediction" (DOP) and the "JEDI doesn't help here" claim

Target audience: internal notes feeding the JCSDA AI strategy memo.
Purpose: systematically evaluate the claim that AI-based direct
observation-to-forecast systems (GraphDOP, Aardvark, FuXi Weather) make a
DA framework like JEDI irrelevant. The claim is half-right; the other half
matters.

---

## What DOP actually is

**Direct Observation Prediction (DOP)** is a family of AI architectures
that skip the classical data assimilation step. Instead of
`observations → DA → analysis → forecast model → forecast`, they go
`observations → neural network → forecast`.

- **GraphDOP / AI-DOP (ECMWF, 2024–2026).** arXiv:2412.15687. GNN trained
  on ~250 B observations (2.5 TB) spanning decades. Uses ATMS, IASI,
  SEVIRI, AMSUA, ASCAT, GPS-RO + conventional surface + radiosonde. No
  reanalysis in the training or inference inputs. Skillful forecasts to
  ~5 days. 2-m temperature forecasts competitive with IFS in the tropics
  at d5.
  [arXiv](https://arxiv.org/abs/2412.15687) ·
  [ECMWF update](https://www.ecmwf.int/en/newsletter/182/earth-system-science/update-ai-dop-skilful-weather-forecasts-produced-directly)
- **Aardvark Weather (Cambridge, Alan Turing Institute, Microsoft, ECMWF,
  2024, *Nature* 2025).** arXiv:2404.00411. End-to-end raw-observation →
  (gridded + station) forecast. 8% of NWP's input data, 1000× less compute.
  [Nature](https://www.nature.com/articles/s41586-025-08897-0).
- **FuXi Weather (Fudan, 2024/2025).** Cyclic 6-hour DA + forecast from raw
  brightness temperatures (FY-3E, Metop-C, NOAA-20) + GNSS-RO. 0.25°
  resolution, 10-day lead. Beats HRES in observation-sparse regions like
  central Africa.
  [arXiv](https://arxiv.org/abs/2408.05472) ·
  [Nat. Commun. 2025](https://www.nature.com/articles/s41467-025-62024-1).
- **FuXi-DA (Fudan, 2025) and FuXi-En4DVar (2024).** *A generalized
  deep-learning DA framework*, built by the *same Fudan team* that built
  FuXi Weather. Critical observation: the most aggressive ML-forecast lab
  in the world **still built a DA framework**. DA isn't being bypassed by
  the front of the field; it is being rewritten in ML form.
  [FuXi-DA](https://www.nature.com/articles/s41612-025-01039-3) ·
  [FuXi-En4DVar](https://agupubs.onlinelibrary.wiley.com/doi/full/10.1029/2024GL111136).

---

## What ECMWF actually says (critical because they're the leader)

From the ECMWF Newsletter 182 editorial by Director-General Florence
Rabier ("Forecasts from observations"):

> *AI-DOP is the most radical AI departure from physics-based forecasting
> methods we are investigating.*

> *Current ML methods still require an optimal starting point for their
> forecasts, and this is provided by data assimilation.*

> *Impressive performance for the first two days, although after that
> performance is currently not as good as that of other forecasting
> methods.*

And from the technical update (NL 182):

> *[GraphDOP] operates directly upon the physical quantities that are
> actually measured... This circumvents the need for complex error
> covariance estimation and enables use of previously unexploitable
> observations like cloudy infrared and visible reflectances.*

This is the most authoritative source-of-truth in the field saying:

1. DOP is an exciting research line, not a replacement.
2. ECMWF is running both paradigms in parallel.
3. DA remains essential as long as AIFS (and the forecast-model generation
   in general) requires a starting point.
4. DOP's medium-range (d3–5) skill is not yet at IFS level.
5. ECMWF's 2026 Annual Seminar explicitly covers end-to-end DA, latent-
   space DA, *and* direct-from-observation methods — as parallel tracks,
   not competitors.

---

## What GraphDOP's own authors say they cannot yet do

From the paper and ECMWF updates:

- **Observation weighting is a known problem.** Satellite sounding
  channels peak in the stratosphere, so the loss function effectively
  underweights tropospheric channels. "Established error covariance
  models used in physics-based systems may serve as guidance." I.e., DA
  expertise is still on GraphDOP's to-do list.
- **Cloud-sensitive channels are problematic.** The loss can be dominated
  by cloud signals. Bias handling is still open.
- **12-hour input observation window is a stated limitation.** Longer
  windows change network architecture.
- **No ensemble / probabilistic forecasts yet.** Deterministic only.
- **No regional or high-resolution extension yet.**
- **No coupled (atm + ocean + sea-ice + wave) extension yet.**
- **Adding a new instrument requires full retraining.** Not a 15-minute
  config file like UFO/IODA.

These are not academic caveats. Each of them is where a DA framework
contributes value.

---

## Honest audit — what DOP removes and what it doesn't

| Function in a traditional DA pipeline | Removed by DOP? |
|---------------------------------------|-----------------|
| Forecast model integration (physics-based) | **Yes** — replaced by NN |
| Variational or ensemble analysis step | **Yes** — skipped |
| Analysis → initial condition | **Yes** — initial condition is raw observations |
| Error covariance estimation (R, B) | **Yes** — implicit in training data |
| BUFR / HDF5 / NetCDF observation ingestion | **No** — still required |
| Observation decoding, unit conversion, coordinate normalization | **No** — every DOP system has an internal equivalent |
| Quality control of grossly wrong observations | **Partially, at best.** DOP is fragile to stuck sensors, broken buoys, bad satellite cycles. No DOP paper reports a production-grade QC story. |
| Bias correction across drifting instruments | **No.** Handled implicitly in training. When a satellite's bias characteristics change mid-operation, DOP requires retraining. JEDI VarBC adapts online. |
| Observation operators for *new* instruments that didn't exist at training time | **No.** DOP cannot ingest new observations until retraining. JEDI can add a new sensor in a week. |
| Coupled atm–ocean–ice–wave DA | **No.** No DOP system handles this as of 2026. |
| Analysis as a product (for reanalysis, downstream apps) | **No.** DOP produces forecasts, not analyses. The reanalysis ecosystem (ERA5, MERRA-2, JRA) is DA-based and will remain so. |
| Forecast sensitivity / observation impact (FSOI) | **No.** DOP has no analysis and no TLM/adjoint, so it does not natively produce per-observation impact — a metric agencies use to value $100M satellite programs. |
| Regional storm-scale DA | **No.** StormCast and related efforts are ML-forecast but not DOP. |
| Training data for the next generation of AI models | **No — in fact, the opposite.** DOP's training fuel is the JEDI/GSI/4D-Var reanalysis era. Without that historical DA investment, GraphDOP and Aardvark would not exist. |

The right half of this table is what JCSDA / JEDI does, and it does not go
away under DOP. In several rows, DOP *depends on* it.

---

## Where the claim "JEDI doesn't help here" is correct

Honest acknowledgment:

1. **The inner DA algorithms of JEDI (oops variational minimizer, SABER B
   chains, the 4D-Var cost) do not directly power a DOP model.** A DOP
   model has no use for a variational minimizer.
2. **If one accepts GraphDOP / FuXi Weather as produced by ECMWF / Fudan
   and consumed by NOAA as a forecast, then JEDI as a *forecasting*
   framework plays no role.**
3. **For the narrow class of problems where DOP is demonstrably adequate
   (global medium-range deterministic, in-distribution variables, mature
   observation coverage), a world without classical DA is thinkable.**

A strategy memo that denies this is not credible.

## Where the claim is wrong or incomplete

1. **DOP does not eliminate the observation infrastructure.** Raw
   BUFR/HDF5 decoding, dataset registration, coordinate transformations,
   and observation archive management are still required for the DOP
   pipeline. IODA is a candidate for that role; every DOP lab has built
   their internal equivalent.
2. **DOP does not eliminate QC and bias correction — it hides them in
   training data.** The moment a production DOP system faces a real-time
   stream with drifting biases or a broken satellite, an online QC layer
   is needed. Nobody has published that yet.
3. **DOP does not handle new observation types.** The training cost of
   adding a new sensor is a model retrain. For the US observing system,
   where new instruments launch every 1–3 years, JEDI's plug-in operator
   architecture is structurally faster.
4. **DOP does not produce analyses.** The analysis product remains a
   first-class deliverable for reanalysis, research, and downstream
   applications (ocean modeling, air quality, emergency response).
   Reanalysis = DA in a loop.
5. **DOP in coupled systems doesn't exist yet.** Atm–ocean–ice DA is a
   JCSDA flagship per §6.6 of the strategy memo. DOP has nothing here.
6. **The most aggressive ML-forecast lab in the world (Fudan) built its
   own DA framework (FuXi-DA, FuXi-En4DVar) *after* building FuXi
   Weather.** If DOP were displacing DA, this would not be the industry
   trajectory.
7. **The ECMWF Director-General explicitly states that current ML methods
   still need an analysis, provided by DA.** The most authoritative voice
   in the field does not endorse the "DA is dead" reading.
8. **DOP depends on DA historically.** Every frontier AI weather model —
   including DOP variants — trained on reanalysis (ERA5, MERRA-2). There
   is no DOP-universe-without-a-reanalysis-era. Preserving the ability to
   produce high-quality reanalyses is a *requirement* for the next
   generation of AI forecasting.

---

## Strategic implications for JCSDA

1. **Do not dismiss DOP.** It is real, it works, and it will take some
   fraction of JEDI's current territory over the next 5–10 years. A
   strategy that ignores DOP is fragile.
2. **Do not panic.** DOP has structural limits that the field itself
   admits (regional, coupled, new-instrument, analysis product, real-time
   QC). JEDI's core competencies are in those limits.
3. **Reframe JEDI's value to the AI era:**
   - The **observation platform** (IODA, UFO operators, QC filters, bias
     correction) that DOP systems consume.
   - The **DA framework for everything DOP can't yet do** — coupled,
     regional, new-instrument, reanalysis.
   - The **evaluation substrate** — because DOP models need rigorous,
     independent evaluation against real observations, and JEDI's
     H(x)+observation pipeline is the natural tool.
   - The **analysis producer** for the reanalysis archives that train the
     *next* generation of AI models.
4. **Build the DA capabilities that make DOP better, not worse.** DOP
   itself wants FSOI-like diagnostics (see
   [arXiv:2510.27388](https://arxiv.org/abs/2510.27388)); wants better
   observation error characterization (ECMWF's own stated limitation);
   wants bias-correction strategies (same); wants QC. All of these are
   JCSDA core competencies.
5. **Do the one thing DOP labs cannot economically do: maintain
   operational-grade observation handling across NOAA, Navy, NASA, USAF
   simultaneously.** Multi-agency neutrality is unique to JCSDA; no
   commercial or academic DOP group can match it.

## The hybrid future to bet on

The plausible 5-year picture is not DA-or-DOP. It is:

- **DOP as a fast short-range nowcasting + medium-range deterministic
  alternative** alongside classical forecasts.
- **Classical (or AI-based) DA** continuing as the analysis producer for
  reanalysis, coupled systems, and regional high-resolution.
- **Hybrid pipelines** where a DA-produced analysis initializes both a
  classical NWP run *and* a DOP-continued forecast, with the user picking
  whichever has lower verified error for their application.
- **A shared observation platform** underneath both — JEDI's opportunity
  to be the canonical US ingestion/QC/bias-correction layer.

The strategy should explicitly name this future and position JCSDA to own
the platform layer.

---

## One-line for the memo

*DOP is a real threat to the forecasting half of DA, not the observation-
science half. The observation platform, coupled DA, reanalysis, and
new-instrument agility are all things DOP does not do, and all things
JCSDA does. The correct response is not denial; it is to reposition JEDI
as the neutral US observation platform beneath both paradigms.*
