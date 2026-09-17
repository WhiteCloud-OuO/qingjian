use qingjian_dictionary::DictionaryError;
use qingjian_learning::LearningError;
use qingjian_lm::LmError;
use qingjian_neural::NeuralError;
use qingjian_platform::ConfigError;
use qingjian_predict::PredictError;
use qingjian_translate::GlossaryError;
#[derive(Debug, thiserror::Error)]
pub enum CliError {
    #[error(transparent)]
    Dictionary(#[from] DictionaryError),

    #[error(transparent)]
    Neural(#[from] NeuralError),

    #[error(transparent)]
    Glossary(#[from] GlossaryError),

    #[error(transparent)]
    Learning(#[from] LearningError),

    /// 学习语言不是 en / ja / es。
    #[error("learning language must be en, ja or es, got {0:?}")]
    Language(String),

    /// `ConfigError` 里的 `toml::de::Error` / `toml_edit::TomlError` 有一百多字节，
    /// 直接放进变体会让 `Result<_, CliError>` 越过 clippy `result_large_err` 的阈值；
    /// 装箱后 `CliError` 只有几十字节，错误路径上一次 `Box` 分配的开销可以忽略。
    /// `#[from]` 不支持自动装箱，下面的 `From` 是手写的。
    #[error(transparent)]
    Config(Box<ConfigError>),

    #[error(transparent)]
    Predict(#[from] PredictError),

    #[error(transparent)]
    LanguageModel(#[from] LmError),

    #[error(transparent)]
    Io(#[from] std::io::Error),

    #[error(transparent)]
    Replay(#[from] crate::replay::ReplayError),

    #[error(transparent)]
    Eval(#[from] crate::eval::EvalError),

    #[error(transparent)]
    Tune(#[from] crate::tuning::TuneError),
}

impl From<ConfigError> for CliError {
    fn from(error: ConfigError) -> Self {
        Self::Config(Box::new(error))
    }
}
