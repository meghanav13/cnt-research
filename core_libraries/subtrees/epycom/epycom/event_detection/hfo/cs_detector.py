# -*- coding: utf-8 -*-
# Copyright (c) St. Anne's University Hospital in Brno. International Clinical
# Research Center, Biomedical Engineering. All Rights Reserved.
# Distributed under the (new) BSD License. See LICENSE.txt for more info.

# Std imports
from multiprocessing import Pool

# Third pary imports
import numpy as np
from scipy.signal import butter, filtfilt, hilbert
from scipy.special import gammaincinv
from numba import njit

# Local imports
from ...utils.method import Method


# %% CS detector

# def cs_detect(data, fs, low_fc, high_fc,
#              threshold, band_detections = True,
#              stat_window_size = 10, cycs_per_detect = 4):
#    """
#    CS detection algorithm.
#
#    CIMBÁLNÍK, Jan, Angela HEWITT, Greg WORRELL and Matt STEAD. \n
#    The CS Algorithm: A Novel Method for High Frequency Oscillation \n
#    Detection in EEG. Journal of Neuroscience Methods [online]. \n
#    2017, vol. 293, pp. 6–16. ISSN 01650270.\n
#    Available at: doi:10.1016/j.jneumeth.2017.08.023
#
#
#
#    Parameters:
#    -----------
#    data(1-d numpy array) - raw data\n
#    fs(int) - sampling frequency\n
#    low_fc(float) - low cut-off frequency\n
#    high_fc(float) - high cut-off frequency\n
#    stat_window_size(float) - statistical window size in secs (default = 10)\n
#    det_window_size(float) - number of cycles in secs (default = 5)\n
#
#    Returns:
#    --------
#    df_out(pandas.DataFrame) - output dataframe with detections\n
#    """
#
#    # Create output dataframe
#
#    df_out = create_output_df()
#
#    return


def detect_hfo_cs_beta(sig, fs=5000, threshold=0.1, cycs_per_detect=4., mp=1):
    """
    Beta version of CS detection algorithm. Which was used to develop
    CS detection algorithm.

    Parameters
    ----------
    sig: numpy array
        1D numpy array with raw data
    fs: int
        Signal sampling frequency
    threshold: float
        Threshold for detection between 0 and 1 (Default=0.1)
    cycs_per_detect: float
        Minimal number of cycles threshold. (Default=4)
    mp: int
        Number of cores to use (def = 1)

    Returns
    -------
    output: list
        List of tuples with the following structure of detections:
        (event_start, event_stop, low_fc, high_fc, amp, fhom, dur, prod,
         is_conglom)

    Note
    ----
    The last object "is_conglom" in the output bool value.
    False stands for detections in single frequency bands whereas True
    stands for conglomerate created from detections in frequency bands that
    overlap in time domain.

    References
    ----------
    [1] J. Cimbalnik, A. Hewitt, G. A. Worrell, and M. Stead, “The CS
    Algorithm: A Novel Method for High Frequency Oscillation Detection
    in EEG,” J. Neurosci. Methods, vol. 293, pp. 6–16, 2017.
    """

    # Create output

    output = []

    # TODO - move the settings to a data file

    constants = {'BAND_STARTS': [44, 52, 62, 73, 86, 102, 121, 143, 169, 199,
                                 237, 280, 332, 392, 464, 549, 650],
                 'BAND_CENTERS': [52, 62, 73, 86, 102, 121, 143, 169, 199, 237,
                                  280, 332, 392, 464, 549, 650, 769],
                 'BAND_STOPS': [62, 73, 86, 102, 121, 143, 169, 199, 237, 280,
                                332, 392, 464, 549, 650, 769, 909],
                 'AMP_KS': [1.13970939, 0.90183703, 1.26436011, 1.03769074,
                            0.85849874, 0.94987266, 0.80845992, 1.67940963,
                            1.04080418, 1.24382275, 1.60240884, 1.10695014,
                            1.17010383, 0.88196648, 1.04245538, 0.70917389,
                            2.21536184],
                 'AMP_THETAS': [1.65277574, 3.48530721, 2.98961385,
                                11.54210813, 18.93869204, 10.11982852,
                                10.53609476, 5.91562993, 11.09205920,
                                8.84505258, 6.92641365, 18.89938640,
                                23.76501855, 30.42839963, 27.30653900,
                                22.48544327, 0.08329301],
                 'AMP_OFFSETS': [6.41469207, 6.39345582, 6.40000914,
                                 7.32380252, 8.32055181, 8.58559154,
                                 8.27742490, 9.97358643, 10.49550234,
                                 12.41888242, 15.86698463, 21.34769474,
                                 21.89082728, 17.18456284, 18.93825748,
                                 16.30660646, 7.69330283],
                 'FHOM_KS': [1.66197234, 1.00540463, 1.79692941, 1.15586041,
                             1.02455216, 1.21727010, 1.12610054, 0.70076969,
                             0.98379084, 1.54577304, 1.51861533, 1.23976157,
                             1.43199934, 1.17238163, 0.58636256, 1.12205645,
                             0.09508500],
                 'FHOM_THETAS': [4.71109440, 6.05698300, 3.84238418,
                                 6.23370380, 7.89603172, 7.87712768,
                                 8.45272550, 10.00101086, 6.58376596,
                                 3.53488296, 5.27183305, 6.36805821,
                                 7.56839088, 8.24757240, 14.90634368,
                                 18.85016717, 260.59793175],
                 'FHOM_OFFSETS': [8.16878678, 10.55275451, 8.07166998,
                                  8.07086829, 8.94105317, 7.75703706,
                                  7.89853517, 7.14019430, 8.17322770,
                                  8.55596745, 6.90226263, 7.17550663,
                                  7.77665423, 9.07663424, 14.82474643,
                                  20.20094041, 17.71110000],
                 'PROD_KS': [0.84905609, 1.01954096, 1.58872304, 1.88690171,
                             1.27908635, 1.06280570, 0.92824868, 1.49057163,
                             1.38457279, 2.14489528, 1.35910370, 1.44452982,
                             1.89318549, 0.92291990, 0.97845756, 1.42279817,
                             0.09633877],
                 'PROD_THETAS': [5.84241875, 2.72996718, 3.68246691,
                                 6.69128325, 10.43308700, 11.90997028,
                                 13.04316866, 6.93301203, 8.31241387,
                                 4.62399907, 7.32859575, 11.79756235,
                                 12.32143937, 26.04107818, 17.76146131,
                                 18.81871472, 195.40205368],
                 'PROD_OFFSETS': [16.32704840, 19.47650057, 16.18710622,
                                  16.34553372, 19.25022797, 18.30852676,
                                  18.15222002, 18.98117587, 19.84269749,
                                  21.64225522, 24.19732683, 25.65335524,
                                  26.52948797, 24.05945634, 38.10559556,
                                  34.94781992, 20.41020467],
                 'DUR_KS': [0.94831016, 1.20644724, 1.19723676, 1.24834990,
                            1.72876216, 1.88991915, 1.45709687, 1.76097598,
                            1.42626762, 1.81104799, 2.09379726, 2.28979796,
                            1.92883462, 2.15155894, 1.14187099, 1.42071107,
                            0.38495461],
                 'DUR_THETAS': [0.04543605, 0.04113687, 0.03842913, 0.03390445,
                                0.02099894, 0.01687568, 0.01622539, 0.00794505,
                                0.00857187, 0.00499798, 0.00489236, 0.00462047,
                                0.00532479, 0.00263985, 0.00623849, 0.01249162,
                                0.00115305],
                 'DUR_OFFSETS': [0.10320000, 0.09316255, 0.06500000,
                                 0.05480000, 0.04420000, 0.03220000,
                                 0.02820000, 0.02580000, 0.02291436,
                                 0.01940000, 0.01760000, 0.01500000,
                                 0.01180000, 0.01000000, 0.01180000,
                                 0.01500000, 0.00844698]}

    nyquist = (fs / 2) - 1
    n_bands = len([x for x in constants['BAND_STOPS'] if x <= nyquist])

    edge_thresh = 0.1

    norm_coefs = [round(len(sig) / 3), round((2 * len(sig)) / 3)]

    conglom_arr = np.zeros([n_bands, len(sig)], 'bool')

    # Create a pool of workers
    if mp > 1:

        work_pool = Pool(mp)

        iter_args = []
        for band_idx in range(n_bands):
            iter_args.append([sig, fs, norm_coefs, band_idx,
                              cycs_per_detect, threshold,
                              edge_thresh, constants])

        band_concat = work_pool.map(_detect_band, iter_args)
        work_pool.join()

        new_dets = [res[0] for res in band_concat]
        output += new_dets
        event_cnt = len(new_dets)

        for band_idx in range(n_bands):
            conglom_arr[band_idx, :] = band_concat[band_idx][1]

    else:
        event_cnt = 0
        for band_idx in range(n_bands):
            args = [sig, fs, norm_coefs, band_idx, cycs_per_detect, threshold,
                    edge_thresh, constants]

            res = _detect_band(args)
            conglom_arr[band_idx, :] = res[1]
            event_cnt += len(res[0])
            output += res[0]

    # Create congloms
    conglom_1d = np.sum(conglom_arr, 0)
    new_det_idx = len(output)
    if any(conglom_1d):
        det_locs = np.where(conglom_1d)[0]
        starts_det_locs = np.where(np.diff(det_locs) > 1)[0] + 1
        stops_det_locs = np.where(np.diff(det_locs) > 1)[0]
        if len(starts_det_locs):
            det_starts = np.concatenate([[det_locs[0]],
                                         det_locs[starts_det_locs]])
            det_stops = np.concatenate([det_locs[stops_det_locs],
                                        [det_locs[-1]]])
        else:
            det_starts = np.array([det_locs[0]])
            det_stops = np.array([det_locs[-1]])

        det_stops += 1

        new_det_idx -= event_cnt

        sub_arr = np.array(output[new_det_idx:])

        # Insert congloms
        for event_start, event_stop in zip(det_starts, det_stops):
            det_arr = sub_arr[(sub_arr[:, 0] >= event_start)
                              & (sub_arr[:, 1] <= event_stop)]
            low_fc = det_arr[:, 2].min()
            high_fc = det_arr[:, 3].max()
            amp = det_arr[:, 4].max()
            fhom = det_arr[:, 5].max()
            prod = det_arr[:, 6].max()
            dur = float(event_stop - event_start) / fs

            output.append((event_start, event_stop, low_fc, high_fc,
                           amp, fhom, dur, prod, True))

    if mp > 1:
        work_pool.close()
    return output


# =============================================================================
# Subfunctions
# =============================================================================

@njit("f8[:](f8[:], f8[:], f8[:])")
def calculate_prods(x_prods, x_fhoms, x_amps):
    """
    Speeds up the _detect_band() fucntion
    """
    for i in range(len(x_prods)):
        if (x_fhoms[i] < 0) and (x_amps[i] < 0):
            x_prods[i] = -x_prods[i]
        if x_prods[i] < 0:
            x_prods[i] = -np.sqrt(-x_prods[i])
        else:
            x_prods[i] = np.sqrt(x_prods[i])

    return x_prods


def _detect_band(args):
    """
    Runs detection in one frequency band
    """

    x = args[0]
    fs = args[1]
    norm_coefs = args[2]
    band_idx = args[3]
    cycs_per_detect = args[4]
    threshold = args[5]
    edge_thresh = args[6]
    constants = args[7]

    conglom_band = np.zeros(len(x), 'bool')
    output = []

    wind_secs = cycs_per_detect / constants['BAND_CENTERS'][band_idx]

    [b, a] = butter(3, [(constants['BAND_CENTERS'][band_idx] / 4) / (fs / 2),
                        constants['BAND_STOPS'][band_idx] / (fs / 2)],
                    'bandpass')

    bp_x = filtfilt(b, a, x)
    [b, a] = butter(3, [constants['BAND_STARTS'][band_idx] / (fs / 2),
                        constants['BAND_STOPS'][band_idx] / (fs / 2)],
                    'bandpass')
    np_x = filtfilt(b, a, x)

    h = hilbert(np_x)
    x_amps = np.abs(h)

    np_x_f = np.cos(np.angle(h))

    h = hilbert(bp_x)
    bp_x_f = np.cos(np.angle(h))
    x_fhoms = _sliding_snr(np_x_f, bp_x_f, fs, wind_secs)

    # Normalization
    #    p1 = round(stat_win_samp / 3)
    #    p2 = round((2 * stat_win_samp) / 3)
    sort_arr = np.sort(x_amps)
    amp_dev = (sort_arr[norm_coefs[1]] - sort_arr[norm_coefs[0]]) / 2
    x_amps = (x_amps - sort_arr[norm_coefs[1]]) / amp_dev
    sort_arr = np.sort(x_fhoms)
    fhom_dev = (sort_arr[norm_coefs[1]] - sort_arr[norm_coefs[0]]) / 2
    x_fhoms = (x_fhoms - sort_arr[norm_coefs[1]]) / fhom_dev

    # Calculate prods with jitted function
    x_prods = calculate_prods(x_amps * x_fhoms, x_amps, x_fhoms)

    sort_arr = np.sort(x_prods)
    prod_dev = (sort_arr[norm_coefs[1]] - sort_arr[norm_coefs[0]]) / 2
    x_prods = (x_prods - sort_arr[norm_coefs[1]]) / prod_dev

    # Threshold calculation
    amp_min = _inverse_gamma_cdf(threshold,
                                 constants['AMP_KS'][band_idx],
                                 constants['AMP_THETAS'][band_idx],
                                 constants['AMP_OFFSETS'][band_idx])
    amp_max = 5 * _inverse_gamma_cdf(.99,
                                     constants['AMP_KS'][band_idx],
                                     constants['AMP_THETAS'][band_idx],
                                     constants['AMP_OFFSETS'][band_idx])
    fhom_min = _inverse_gamma_cdf(threshold,
                                  constants['FHOM_KS'][band_idx],
                                  constants['FHOM_THETAS'][band_idx],
                                  constants['FHOM_OFFSETS'][band_idx])
    fhom_max = 5 * _inverse_gamma_cdf(.99,
                                      constants['FHOM_KS'][band_idx],
                                      constants['FHOM_THETAS'][band_idx],
                                      constants['FHOM_OFFSETS'][band_idx])
    prod_min = _inverse_gamma_cdf(threshold,
                                  constants['PROD_KS'][band_idx],
                                  constants['PROD_THETAS'][band_idx],
                                  constants['PROD_OFFSETS'][band_idx])
    prod_max = 5 * _inverse_gamma_cdf(.99,
                                      constants['PROD_KS'][band_idx],
                                      constants['PROD_THETAS'][band_idx],
                                      constants['PROD_OFFSETS'][band_idx])
    dur_min = _inverse_gamma_cdf(threshold,
                                 constants['DUR_KS'][band_idx],
                                 constants['DUR_THETAS'][band_idx],
                                 constants['DUR_OFFSETS'][band_idx])
    dur_max = 5 * _inverse_gamma_cdf(.99,
                                     constants['DUR_KS'][band_idx],
                                     constants['DUR_THETAS'][band_idx],
                                     constants['DUR_OFFSETS'][band_idx])

    # Detect
    j = 0

    while j < len(x):
        if x_prods[j] > edge_thresh:
            event_start = j
            j += 1
            while j < len(x) and x_prods[j] > edge_thresh:
                j += 1

            event_stop = j

            # Calculate duration
            dur = float(event_stop - event_start + 1) / fs
            if (dur < dur_min) or (dur > dur_max):
                j += 1
                continue
            dur_scale = np.sqrt(dur / wind_secs)

            # Calculate amplitude
            amp = np.mean(x_amps[event_start:event_stop])
            amp = amp * dur_scale
            if (amp < amp_min) or (amp > amp_max):
                j += 1
                continue

            # Calculate fhom
            fhom = np.mean(x_fhoms[event_start:event_stop])
            fhom = fhom * dur_scale
            if (fhom < fhom_min) or (fhom > fhom_max):
                j += 1
                continue

            # Calculate product
            prod = np.mean(x_prods[event_start:event_stop])
            prod = prod * dur_scale
            if (prod < prod_min) or (prod > prod_max):
                j += 1
                continue

            conglom_band[event_start:event_stop] = 1

            # Put in output-df
            output.append((event_start, event_stop,
                           constants['BAND_STARTS'][band_idx],
                           constants['BAND_STOPS'][band_idx],
                           amp, fhom, dur, prod, False))
        else:
            j += 1

    return [output, conglom_band]


def _inverse_gamma_cdf(p, k, theta, offset):
    """
    Inverse gamma cumulative distribution function.
    """

    x = gammaincinv(k, p)
    x = (x * theta) + offset

    return x


def _sliding_snr(np_x, bp_x, fs, wind_secs):
    """
    "Signal-to-noise ratio" like metric that compares narrow band and broad
    band signals to eliminate increased power generated by sharp transients.

    Parameters
    ----------
    np_x: np.ndarray
      Narrow band signal
    bp_x: np.ndarray
      Broad band signal
    fs: float
      Sampling frequency
    wind_secs: float
      Sliding window size (seconds)

    Returns
    -------
    snr: np.ndarray
      "Signal-to-noise ratio" like metric

    """

    # Define starting values
    wind = fs * wind_secs
    half_wind = int(round(wind / 2))
    wind = int(round(wind))

    N = min([len(np_x), len(bp_x)])

    snr = np.zeros([N])

    npxx = 0
    bpxx = 0

    # Fill in the beginning and initial window values
    for i in range(int(wind)):
        t1 = np_x[i]
        npxx = npxx + (t1 * t1)
        t2 = bp_x[i] - t1
        bpxx = bpxx + (t2 * t2)

    np_rms = np.sqrt(float(npxx) / wind)
    bp_rms = np.sqrt(float(bpxx) / wind)

    snr[:half_wind] = (np_rms / bp_rms)

    # Slide the window

    np_x_sqr = np.square(np_x)
    np_bp_x_diff_sqr = np.square(bp_x - np_x)

    if wind % 2:
        np_x_sqr_diffs = np_x_sqr[2 * half_wind:] - \
                         np_x_sqr[1:-((2 * half_wind) - 1)]
        np_bp_x_diff_sqr_diffs = np_bp_x_diff_sqr[
                                 2 * half_wind:] - np_bp_x_diff_sqr[1:-((2 * half_wind) - 1)]
    else:
        np_x_sqr_diffs = np_x_sqr[2 * half_wind -
                                  1:-1] - np_x_sqr[1:-((2 * half_wind) - 1)]
        np_bp_x_diff_sqr_diffs = np_bp_x_diff_sqr[
                                 2 * half_wind - 1:-1] - np_bp_x_diff_sqr[1:-((2 * half_wind) - 1)]

    npxx_sig = np.cumsum(np_x_sqr_diffs) + npxx
    bpxx_sig = np.cumsum(np_bp_x_diff_sqr_diffs) + bpxx

    snr[half_wind:-half_wind] = npxx_sig / bpxx_sig

    # ----- Original code -----
    #     Slide the window
    #    i = 1
    #    for k in range(int(N-wind+1)):
    #        p = k + wind - 1
    #
    #        #Beginning of the window
    #        t1 = np_x[i]
    #        npxx = npxx - (t1 * t1)
    #        t2 = bp_x[i] - t1
    #        bpxx = bpxx - (t2 * t2)
    #
    #        #End of the window
    #        t1 = np_x[p]
    #        npxx = npxx + (t1 * t1)
    #        t2 = bp_x[p] - t1
    #        bpxx = bpxx + (t2 * t2)
    #
    #        np_rms = np.sqrt(float(npxx) / wind) # Unnecessary to divide by wind
    #        bp_rms = np.sqrt(float(bpxx) / wind)
    #
    #        snr[k+half_wind] = (np_rms/bp_rms)
    #
    #        i += 1
    # ----- -----

    # Fill in the end
    snr[-half_wind:] = snr[-(half_wind + 1)]

    return snr


class CSDetector(Method):
    algorithm = 'CS_DETECTOR'
    algorithm_type = 'event'
    version = '1.0.0b1'
    dtype = [('event_start', 'int32'),
             ('event_stop', 'int32'),
             ('low_fc', 'float32'),
             ('high_fc', 'float32'),
             ('amp', 'float32'),
             ('fhom', 'float32'),
             ('dur', 'float32'),
             ('prod', 'float32'),
             ('type', 'bool')]

    def __init__(self, **kwargs):
        """
        Beta version of CS detection algorithm. Which was used to develop
        CS detection algorithm.

        Parameters
        ----------
        fs: int
            Signal sampling frequency
        threshold: float
            Threshold for detection between 0 and 1 (Default=0.1)
        cycs_per_detect: float
            Minimal number of cycles threshold. (Default=4)
        low_fc: float
            Low cut-off frequency
        high_fc: float
            High cut-off frequency
        mp: int
            Number of cores to use (def = 1)
        sample_offset: int
            Offset which is added to the final detection. This is used when the
            function is run in separate windows. Default = 0

        References
        ----------
        [1] J. Cimbalnik, A. Hewitt, G. A. Worrell, and M. Stead, “The CS
        Algorithm: A Novel Method for High Frequency Oscillation Detection
        in EEG,” J. Neurosci. Methods, vol. 293, pp. 6–16, 2017.
        """

        super().__init__(detect_hfo_cs_beta, **kwargs)
