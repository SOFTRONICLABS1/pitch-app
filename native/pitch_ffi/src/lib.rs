use pitch_detection::detector::autocorrelation::AutocorrelationDetector;
use pitch_detection::detector::mcleod::McLeodDetector;
use pitch_detection::detector::yin::YINDetector;
use pitch_detection::detector::PitchDetector;

#[repr(C)]
pub struct PitchResult {
    pub frequency: f32,
    pub clarity: f32,
}

#[no_mangle]
pub extern "C" fn pitch_detect(
    signal_ptr: *const f32,
    len: usize,
    sample_rate: u32,
    power_threshold: f32,
    clarity_threshold: f32,
    detector: i32, // 0 = McLeod, 1 = Autocorrelation, 2 = YIN
) -> PitchResult {
    if signal_ptr.is_null() || len == 0 {
        return PitchResult {
            frequency: -1.0,
            clarity: 0.0,
        };
    }

    let signal = unsafe { std::slice::from_raw_parts(signal_ptr, len) };
    let padding = len / 2;

    let result = match detector {
        1 => {
            let mut d = AutocorrelationDetector::<f32>::new(len, padding);
            d.get_pitch(
                signal,
                sample_rate as usize,
                power_threshold,
                clarity_threshold,
            )
        }
        2 => {
            let mut d = YINDetector::<f32>::new(len, padding);
            d.get_pitch(
                signal,
                sample_rate as usize,
                power_threshold,
                clarity_threshold,
            )
        }
        _ => {
            let mut d = McLeodDetector::<f32>::new(len, padding);
            d.get_pitch(
                signal,
                sample_rate as usize,
                power_threshold,
                clarity_threshold,
            )
        }
    };

    match result {
        Some(p) => PitchResult {
            frequency: p.frequency,
            clarity: p.clarity,
        },
        None => PitchResult {
            frequency: -1.0,
            clarity: 0.0,
        },
    }
}
