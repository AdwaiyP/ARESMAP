# 11 — Scientific Basis, Mathematical Formulas & Citations

ARES integrates peer-reviewed planetary physics, aerospace path-planning algorithms, and NASA/JPL mission datasets. This document explains the scientific foundations implemented across the codebase and provides full citations so all original authors and mission teams receive proper credit.

---

## 1. Mars Timekeeping & Orbital Ephemeris
**Implementation:** [`backend/app/services/mars_time.py`](../backend/app/services/mars_time.py)

### Mathematical Formulation
1. **Julian Date (TT) & J2000 Epoch Offset:**
   $$\mathrm{JD}_{\mathrm{TT}} = \mathrm{JD}_{\mathrm{UTC}} + \frac{69.184}{86400}, \qquad \Delta t_{\mathrm{J2000}} = \mathrm{JD}_{\mathrm{TT}} - 2451545.0$$
2. **Mars Sol Date (MSD) & Coordinated Mars Time (MTC):**
   $$\mathrm{MSD} = \frac{\Delta t_{\mathrm{J2000}} - 4.5}{1.0274912517} + 44796.0 - 0.0009626, \qquad \mathrm{MTC} = (\mathrm{MSD} \bmod 1) \times 24\text{ h}$$
3. **Areocentric Solar Longitude ($L_s$) & Equation of Time ($\mathrm{EOT}$):**
   - Mean anomaly $M$ and fictitious mean sun $\alpha_{\mathrm{FMS}}$ advance linearly from J2000.
   - True anomaly equation-of-center $(\nu - M)$ is evaluated via a 5-harmonic Fourier series in $M$ plus 7 planetary perturbation cosine terms ($\sum A_i \cos(0.985626\,\Delta t / \tau_i + \phi_i)$).
   - $L_s = (\alpha_{\mathrm{FMS}} + (\nu - M)) \bmod 360^\circ$.
   - $\mathrm{LTST} = \mathrm{LMST} + \mathrm{EOT}$, where $\mathrm{LMST} = \mathrm{MTC} + \lambda_{\mathrm{east}} / 15^\circ$.
4. **Earth–Mars One-Way Light Time (OWLT):**
   - Computes heliocentric Cartesian coordinates $(x, y, z)$ for Earth and Mars from J2000 Keplerian elements and scales Euclidean separation by the IAU light-time constant (`499.004783836 s/AU`).

### Citations
- **Allison, M., & McEwen, M. (2000).** *A post-Pathfinder evaluation of areocentric solar coordinates with improved timing recipes for Mars seasonal/diurnal climate studies.* Planetary and Space Science, 48(2–3), 215–235. [DOI: 10.1016/S0032-0633(99)00092-6](https://doi.org/10.1016/S0032-0633(99)00092-6)
- **Clancy, R. T., Sandor, B. J., Wolff, M. J., Christensen, P. R., Smith, M. D., Pearl, J. C., Conrath, B. J., & Wilson, R. J. (2000).** *An intercomparison of ground-based millimeter, MGS TES, and Viking atmospheric temperature measurements: Seasonal and interannual variability of temperatures and dust loading in the global Mars atmosphere.* Journal of Geophysical Research: Planets, 105(E4), 9553–9571. *(Defines the Mars Year 1 epoch at $L_s = 0^\circ$ on 1955-04-11.)*
- **NASA Goddard Institute for Space Studies (GISS).** *Mars24 Sunclock — Technical Notes on Mars Solar Time.* https://www.giss.nasa.gov/tools/mars24/help/algorithm.html

---

## 2. Surface Ionizing Radiation & Space Weather
**Implementation:** [`backend/app/services/radiation.py`](../backend/app/services/radiation.py)

### Physical Model
1. **Atmospheric Column Shielding (Hydrostatic Scale Height):**
   $$\Sigma(z) = \Sigma_{\mathrm{ref}} \exp\!\left(-\frac{z - z_{\mathrm{ref}}}{H}\right)$$
   where $\Sigma_{\mathrm{ref}} = 21.4\text{ g/cm}^2$ at Gale Crater ($z_{\mathrm{ref}} = -4500\text{ m}$) and Mars atmospheric scale height $H = 11.1\text{ km}$.
2. **GCR Surface Dose Rate:**
   - Anchored to the Curiosity MSL RAD quiet-Sun surface average of **`0.67 mSv/day`** at Gale Crater, modulated by atmospheric column depth, a `0.88×` attenuation factor inside the Southern Highlands crustal magnetic anomaly (Terra Sirenum / Terra Cimmeria), and a polar latitude enhancement above $|\phi| > 55^\circ$.
3. **Solar Energetic Particle (SEP) Alerting:**
   - Queries NASA's live CCMC **DONKI** (Database Of Notifications, Knowledge, Information) SEP endpoint (`https://api.kauai.ccmc.gsfc.nasa.gov/DONKI/SEP`) to flag active solar storm hazards (`NOMINAL` / `CAUTION` / `HAZARD`).

### Citations
- **Hassler, D. M., Zeitlin, C., Wimmer-Schweingruber, R. F., Ehresmann, B., Rafkin, S., Eigenbrode, J. L., et al. (2014).** *Mars' Surface Radiation Environment Measured with the Mars Science Laboratory's Curiosity Rover.* Science, 343(6169), 1244797. [DOI: 10.1126/science.1244797](https://doi.org/10.1126/science.1244797)
- **Acuña, M. H., Connerney, J. E. P., Ness, N. F., Lin, R. P., Mitchell, D., Carlson, C. W., et al. (1999).** *Global Distribution of Crustal Magnetization Discovered by the Mars Global Surveyor MAG/ER Experiment.* Science, 284(5415), 790–793.
- **NASA Community Coordinated Modeling Center (CCMC).** *Space Weather Database Of Notifications, Knowledge, Information (DONKI).* https://ccmc.gsfc.nasa.gov/tools/DONKI/

---

## 3. Diurnal Surface Climate Prediction
**Implementation:** [`backend/app/services/climate_predictor.py`](../backend/app/services/climate_predictor.py)

### Model & Physics Extrapolation
- **Diurnal Harmonic Encoding + RandomForest:** Minute-of-sol $t \in [0, 1440)$ is encoded as 2nd-order Fourier harmonics ($\sin/\cos$ of $2\pi t / 1440$ and $4\pi t / 1440$) alongside $(\phi, \lambda, z)$ and passed to 10 `scikit-learn` RandomForest regressors trained on **Mars 2020 MEDA Sol 100** telemetry at Jezero Crater ($18.4447^\circ\text{N}, 77.4508^\circ\text{E}, -2569\text{ m}$).
- **Barometric & Insolation Extrapolation:**
  - Pressure scales hydrostatically: $P(z) = P_0 \exp(-(z - z_{\mathrm{ref}}) / 11100\text{ m})$.
  - Air/ground temperatures apply empirical topographic lapse adjustments ($-1.5\text{ K/km}$ air, $-1.8\text{ K/km}$ ground) and cosine-latitude insolation scaling ($\cos\phi / \cos\phi_{\mathrm{ref}}$).
  - Suit differential pressure reports $\Delta P = (29.6\text{ kPa} - P_{\mathrm{ambient}})$.

### Citations
- **Rodriguez-Manfredi, J. A., de la Torre Juárez, M., Alonso, A., Apéstigue, V., Arruego, I., Atienza, T., et al. (2021).** *The Mars Environmental Dynamics Analyzer, MEDA. A Suite of Environmental Sensors for the Mars 2020 Mission.* Space Science Reviews, 217, 48. [DOI: 10.1007/s11214-021-00816-9](https://doi.org/10.1007/s11214-021-00816-9)
- **Breiman, L. (2001).** *Random Forests.* Machine Learning, 45(1), 5–32.
- **NASA Planetary Data System (PDS) Atmospheres Node.** *Mars 2020 Perseverance MEDA Derived Data Products.*

---

## 4. EVA Traverse Pathfinding, Line-of-Sight & Safety Validation
**Implementations:** [`backend/app/services/astar.py`](../backend/app/services/astar.py), [`backend/app/services/theta_star.py`](../backend/app/services/theta_star.py), [`backend/app/services/safety.py`](../backend/app/services/safety.py)

### Algorithms
1. **8-Connected A\* Search:** Minimizes $f(n) = g(n) + h(n)$ with admissible Euclidean metric heuristic $h(n)$ and edge cost $\Delta d + w_{\mathrm{slope}}\theta_{\mathrm{deg}} + w_{\mathrm{risk}} r$, rejecting edges exceeding `max_slope_deg`.
2. **Theta\* Any-Angle Path Planning:** Relaxes grid-heading constraints by checking Line-of-Sight (LOS) directly from `parent(s)` to `neighbor(s')`, yielding shorter, smoother trajectories with lower cumulative elevation gain.
3. **Conservative Grid Supercover LOS:** Traverses every grid cell intersected by a continuous segment (including corner-touching cells) to guarantee fail-closed obstacle and slope safety.

### Citations
- **Hart, P. E., Nilsson, N. J., & Raphael, B. (1968).** *A Formal Basis for the Heuristic Determination of Minimum Cost Paths.* IEEE Transactions on Systems Science and Cybernetics, 4(2), 100–107. [DOI: 10.1109/TSSC.1968.300136](https://doi.org/10.1109/TSSC.1968.300136)
- **Daniel, K., Nash, A., Koenig, S., & Felner, A. (2010).** *Theta\*: Any-Angle Path Planning on Grids.* Journal of Artificial Intelligence Research (JAIR), 39, 533–579. [DOI: 10.1613/jair.2994](https://doi.org/10.1613/jair.2994)
- **Amanatides, J., & Woo, A. (1987).** *A Fast Voxel Traversal Algorithm for Ray Tracing.* Eurographics '87, 3–10. *(Basis for conservative grid supercover line traversal.)*

---

## 5. Space-Link Error Detection & Correction (EDAC)
**Implementation:** [`backend/app/services/space_edac.py`](../backend/app/services/space_edac.py)

- **Hamming(7,4) Block Coding:** Encodes each 4-bit nibble into a 7-bit codeword with 3 parity bits ($p_1, p_2, p_3$), computing a 3-bit syndrome on decode to detect and correct any single-bit radiation-induced upset (SEU) per nibble.
- **CRC-32 Checksums:** Attaches IEEE 802.3 CRC-32 integrity headers (`X-Space-CRC32`) to spatial payloads.

### Citations
- **Hamming, R. W. (1950).** *Error Detecting and Error Correcting Codes.* Bell System Technical Journal, 29(2), 147–160. [DOI: 10.1002/j.1538-7305.1950.tb00463.x](https://doi.org/10.1002/j.1538-7305.1950.tb00463.x)

---

## 6. Planetary Imagery, Topography & Spatial Interpolation
**Implementations:** [`backend/app/api/map_data.py`](../backend/app/api/map_data.py), [`backend/app/services/eva_local.py`](../backend/app/services/eva_local.py)

### Spatial Interpolation
- **Inverse Distance Weighting (IDW):** When building local terrain elevation grids from sparse MongoDB spatial features, elevations are interpolated via Shepard's IDW formula:
  $$\hat{z}(x) = \frac{\sum_i w_i(x)\, z_i}{\sum_i w_i(x)}, \qquad w_i(x) = \frac{1}{d(x, x_i)^p + \epsilon}$$

### Planetary Data Sources & Mission Credits
- **MOLA (Mars Orbiter Laser Altimeter) Global DEM:**
  - Smith, D. E., Zuber, M. T., Frey, H. V., Garvin, J. B., Head, J. W., Muhleman, D. O., et al. (2001). *Mars Orbiter Laser Altimeter: Experiment summary after the first year of global mapping of Mars.* Journal of Geophysical Research: Planets, 106(E10), 23689–23722.
- **THEMIS (Thermal Emission Imaging System) Day/Night IR & Blended Mosaics:**
  - Christensen, P. R., Jakosky, B. M., Kieffer, H. H., Malin, M. C., McSween, H. Y., Nealson, K., et al. (2004). *The Thermal Emission Imaging System (THEMIS) for the Mars 2001 Odyssey Mission.* Space Science Reviews, 110, 85–130.
- **NASA Mars Trek WMTS & USGS Astrogeology Science Center WMS:**
  - Global/regional Mars imagery and shaded-relief elevation tiles (`https://trek.nasa.gov/tiles/Mars/...`, `https://planetarymaps.usgs.gov/cgi-bin/mapserv`).
- **Curiosity (MSL) & Perseverance (Mars 2020) Rover Imagery & Waypoints:**
  - NASA/JPL-Caltech PDS Imaging Node & Mars 2020 / MSL Navcam, Mastcam, and Hazcam public mission archives.
- **Shepard, D. (1968).** *A two-dimensional interpolation function for irregularly-spaced data.* Proceedings of the 23rd ACM National Conference, 517–524. *(Basis for IDW elevation blending.)*
