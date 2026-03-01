#pragma once

#include <algorithm>
#include <cassert>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <memory>
#include <utility>
#include <vector>

namespace juce {

template <typename T>
inline T jmin(T a, T b) {
    return std::min(a, b);
}

template <typename T>
inline T jmax(T a, T b) {
    return std::max(a, b);
}

template <typename... Args>
inline void ignoreUnused(Args &&...) {}

#ifndef jassert
#define jassert(expression) assert(expression)
#endif

template <typename T>
class HeapBlock {
  public:
    HeapBlock() = default;

    explicit HeapBlock(size_t size) { calloc(size); }

    void calloc(size_t size) { data_.assign(size, T{}); }

    void clear(size_t count) {
        if (count > data_.size()) {
            count = data_.size();
        }
        std::fill_n(data_.data(), count, T{});
    }

    T *getData() { return data_.data(); }

    const T *getData() const { return data_.data(); }

    T &operator[](size_t index) { return data_[index]; }

    const T &operator[](size_t index) const { return data_[index]; }

  private:
    std::vector<T> data_;
};

struct FloatVectorOperations {
    static void fill(float *dest, float value, int numSamples) { std::fill_n(dest, numSamples, value); }

    static void subtract(float *dest, const float *src, int numSamples) {
        for (int i = 0; i < numSamples; ++i) {
            dest[i] -= src[i];
        }
    }

    static void multiply(float *dest, float value, int numSamples) {
        for (int i = 0; i < numSamples; ++i) {
            dest[i] *= value;
        }
    }

    static void add(float *dest, float value, int numSamples) {
        for (int i = 0; i < numSamples; ++i) {
            dest[i] += value;
        }
    }

    static void copy(float *dest, const float *src, int numSamples) { std::copy_n(src, numSamples, dest); }

    static void abs(float *dest, const float *src, int numSamples) {
        for (int i = 0; i < numSamples; ++i) {
            dest[i] = std::fabs(src[i]);
        }
    }

    static void clip(float *dest, const float *src, float low, float high, int numSamples) {
        for (int i = 0; i < numSamples; ++i) {
            dest[i] = std::max(low, std::min(high, src[i]));
        }
    }
};

template <typename T>
class AudioBuffer {
  public:
    AudioBuffer() = default;

    AudioBuffer(int channels, int samples) { setSize(channels, samples); }

    AudioBuffer(T *const *channels, int channelCount, int sampleCount)
        : numChannels_(channelCount), numSamples_(sampleCount), owning_(false) {
        channelPointers_.resize(channelCount);
        for (int index = 0; index < channelCount; ++index) {
            channelPointers_[index] = channels[index];
        }
    }

    void setSize(int channels, int samples, bool keepExistingContent = false, bool clearExtraSpace = true) {
        const int oldChannels = numChannels_;
        const int oldSamples = numSamples_;
        std::vector<T> oldStorage;

        if (keepExistingContent && owning_) {
            oldStorage = storage_;
        }

        numChannels_ = channels;
        numSamples_ = samples;
        owning_ = true;
        storage_.assign(static_cast<size_t>(channels * samples), T{});
        channelPointers_.resize(channels);

        for (int channel = 0; channel < channels; ++channel) {
            channelPointers_[channel] = storage_.data() + (channel * samples);
        }

        if (keepExistingContent && !oldStorage.empty()) {
            const int copyChannels = std::min(oldChannels, channels);
            const int copySamples = std::min(oldSamples, samples);
            for (int channel = 0; channel < copyChannels; ++channel) {
                std::copy_n(oldStorage.data() + (channel * oldSamples), copySamples, getWritePointer(channel));
            }
        }

        if (!clearExtraSpace && keepExistingContent) {
            return;
        }
    }

    void clear() {
        for (int channel = 0; channel < numChannels_; ++channel) {
            clear(channel, 0, numSamples_);
        }
    }

    void clear(int channel, int startSample, int numSamples) {
        auto *dest = getWritePointer(channel) + startSample;
        std::fill_n(dest, numSamples, T{});
    }

    int getNumChannels() const { return numChannels_; }

    int getNumSamples() const { return numSamples_; }

    T *getWritePointer(int channel) { return channelPointers_[channel]; }

    const T *getReadPointer(int channel) const { return channelPointers_[channel]; }

    void makeCopyOf(const AudioBuffer<T> &other, bool /*avoidReallocating*/) {
        setSize(other.getNumChannels(), other.getNumSamples());
        for (int channel = 0; channel < numChannels_; ++channel) {
            std::copy_n(other.getReadPointer(channel), numSamples_, getWritePointer(channel));
        }
    }

    void copyFrom(int destChannel,
                  int destStartSample,
                  const AudioBuffer<T> &source,
                  int sourceChannel,
                  int sourceStartSample,
                  int numSamples,
                  T gain = static_cast<T>(1)) {
        auto *dest = getWritePointer(destChannel) + destStartSample;
        const auto *src = source.getReadPointer(sourceChannel) + sourceStartSample;
        if (gain == static_cast<T>(1)) {
            std::copy_n(src, numSamples, dest);
            return;
        }
        for (int i = 0; i < numSamples; ++i) {
            dest[i] = src[i] * gain;
        }
    }

    void addFrom(int destChannel,
                 int destStartSample,
                 const AudioBuffer<T> &source,
                 int sourceChannel,
                 int sourceStartSample,
                 int numSamples,
                 T gain = static_cast<T>(1)) {
        auto *dest = getWritePointer(destChannel) + destStartSample;
        const auto *src = source.getReadPointer(sourceChannel) + sourceStartSample;
        for (int i = 0; i < numSamples; ++i) {
            dest[i] += src[i] * gain;
        }
    }

    void applyGain(T gain) {
        for (int channel = 0; channel < numChannels_; ++channel) {
            auto *dest = getWritePointer(channel);
            for (int i = 0; i < numSamples_; ++i) {
                dest[i] *= gain;
            }
        }
    }

  private:
    int numChannels_ = 0;
    int numSamples_ = 0;
    bool owning_ = true;
    std::vector<T> storage_;
    std::vector<T *> channelPointers_;
};

} // namespace juce

namespace qs {
namespace dsp {

constexpr float root2 = 1.41421356f;
constexpr int COEFFICIENTS_RATE = 48000;

struct Coefficients {
    double b0 = 1.0;
    double b1 = 0.0;
    double b2 = 0.0;
    double a0 = 0.0;
    double a1 = 0.0;
    double a2 = 0.0;
    int sampleRate = COEFFICIENTS_RATE;

    Coefficients() = default;

    Coefficients(double b0In, double b1In, double b2In, double a0In, double a1In, double a2In)
        : b0(b0In), b1(b1In), b2(b2In), a0(a0In), a1(a1In), a2(a2In) {}
};

struct EnvelopeTiming {
    float attackMS = 5.0f;
    float releaseMS = 5.0f;
};

inline float safeLog10(float value) { return std::log10(value + 1e-12f); }

inline void log10Channels(juce::AudioBuffer<float> &buffer) {
    for (int channel = 0; channel < buffer.getNumChannels(); ++channel) {
        auto *samples = buffer.getWritePointer(channel);
        for (int index = 0; index < buffer.getNumSamples(); ++index) {
            samples[index] = safeLog10(samples[index]);
        }
    }
}

class Envelope {
  public:
    Envelope(EnvelopeTiming timing, int numChannels)
        : attackMS_(timing.attackMS), releaseMS_(timing.releaseMS), numChannels_(numChannels) {
        hist_.calloc(static_cast<size_t>(numChannels_));
    }

    void prepare(float sampleRate) {
        const float samplesPerMS = sampleRate * 0.001f;
        attack_ = std::pow(0.01f, 1.0f / (juce::jmax(attackMS_, 1.0f) * samplesPerMS));
        release_ = std::pow(0.01f, 1.0f / (juce::jmax(releaseMS_, 1.0f) * samplesPerMS));
    }

    void process(juce::AudioBuffer<float> &buffer) {
        const int numChannels = juce::jmin(numChannels_, buffer.getNumChannels());
        for (int channel = 0; channel < numChannels; ++channel) {
            processChannel(buffer, channel);
        }
    }

    void reset() { hist_.clear(static_cast<size_t>(numChannels_)); }

  private:
    void processChannel(juce::AudioBuffer<float> &buffer, int channel) {
        auto *samples = buffer.getWritePointer(channel);
        for (int index = 0; index < buffer.getNumSamples(); ++index) {
            const float squared = samples[index] * samples[index];
            hist_[static_cast<size_t>(channel)] =
                (squared > hist_[static_cast<size_t>(channel)] ? attack_ : release_) *
                    (hist_[static_cast<size_t>(channel)] - squared) +
                squared;
            samples[index] = std::sqrt(hist_[static_cast<size_t>(channel)]);
        }
    }

    juce::HeapBlock<float> hist_;
    float attack_ = 0.0f;
    float release_ = 0.0f;
    float attackMS_ = 0.0f;
    float releaseMS_ = 0.0f;
    int numChannels_ = 0;
};

class IIRFilter {
  public:
    explicit IIRFilter(Coefficients coefficients) : coeffs_(coefficients), coeffsQuant_(coefficients) {
        hist1_.calloc(static_cast<size_t>(numChannels_));
        hist2_.calloc(static_cast<size_t>(numChannels_));

        const double d = coeffs_.a2 - coeffs_.a1 + 1.0;
        const double k = std::sqrt((coeffs_.a1 + coeffs_.a2 + 1.0) / d);

        q_ = k / ((2.0 - 2.0 * coeffs_.a2) / d);
        arctanK_ = std::atan(k);
        vl_ = (coeffs_.b0 + coeffs_.b1 + coeffs_.b2) / (coeffs_.a1 + coeffs_.a2 + 1.0);
        vb_ = (coeffs_.b0 - coeffs_.b2) / (1.0 - coeffs_.a2);
        vh_ = (coeffs_.b0 - coeffs_.b1 + coeffs_.b2) / (coeffs_.a2 - coeffs_.a1 + 1.0);
    }

    void prepare(float sampleRate, int numChannels) {
        numChannels_ = numChannels;
        hist1_.calloc(static_cast<size_t>(numChannels_));
        hist2_.calloc(static_cast<size_t>(numChannels_));

        if (static_cast<int>(sampleRate) == coeffs_.sampleRate) {
            coeffsQuant_ = coeffs_;
            return;
        }

        const double targetRate = static_cast<double>(sampleRate);
        const double coeffRate = static_cast<double>(coeffs_.sampleRate);
        const double k = std::tan(arctanK_ * coeffRate / targetRate);
        const double k2 = k * k;
        const double kdq = k / q_;

        const double a0 = k2 + kdq + 1.0;
        coeffsQuant_.a1 = 2.0 * (k2 - 1.0) / a0;
        coeffsQuant_.a2 = (1.0 - kdq + k2) / a0;

        const double l = vl_ * k2;
        const double b = vb_ * kdq;
        coeffsQuant_.b0 = (l + b + vh_) / a0;
        coeffsQuant_.b1 = 2.0 * (l - vh_) / a0;
        coeffsQuant_.b2 = (l - b + vh_) / a0;
    }

    void process(juce::AudioBuffer<float> &buffer) {
        const int numChannels = juce::jmin(numChannels_, buffer.getNumChannels());
        const double a1 = coeffsQuant_.a1;
        const double a2 = coeffsQuant_.a2;
        const double b0 = coeffsQuant_.b0;
        const double b1 = coeffsQuant_.b1;
        const double b2 = coeffsQuant_.b2;

        for (int channel = 0; channel < numChannels; ++channel) {
            auto *samples = buffer.getWritePointer(channel);
            for (int index = 0; index < buffer.getNumSamples(); ++index) {
                const double input = samples[index];
                const double f = input - (a1 * hist1_[static_cast<size_t>(channel)]) -
                                 (a2 * hist2_[static_cast<size_t>(channel)]);
                const double out =
                    (b0 * f) + (b1 * hist1_[static_cast<size_t>(channel)]) + (b2 * hist2_[static_cast<size_t>(channel)]);

                hist2_[static_cast<size_t>(channel)] = hist1_[static_cast<size_t>(channel)];
                hist1_[static_cast<size_t>(channel)] = f;
                samples[index] = static_cast<float>(out);
            }
        }
    }

    void reset() {
        hist1_.clear(static_cast<size_t>(numChannels_));
        hist2_.clear(static_cast<size_t>(numChannels_));
    }

  private:
    int numChannels_ = 1;
    Coefficients coeffs_;
    Coefficients coeffsQuant_;
    double q_ = 0.0;
    double vh_ = 0.0;
    double vb_ = 0.0;
    double vl_ = 0.0;
    double arctanK_ = 0.0;
    juce::HeapBlock<double> hist1_;
    juce::HeapBlock<double> hist2_;
};

class HilbertTransform {
  public:
    void process(juce::AudioBuffer<float> &buffer, int realChannel, int imagChannel, int sourceChannel) {
        const auto *source = buffer.getReadPointer(sourceChannel);
        auto *real = buffer.getWritePointer(realChannel);
        auto *imag = buffer.getWritePointer(imagChannel);
        for (int index = 0; index < buffer.getNumSamples(); ++index) {
            tick(real[index], imag[index], source[index]);
        }
    }

    void prepare(float sampleRate) {
        calculateCoefficients(sampleRate);
        initialized_ = true;
    }

    void reset() {
        x1_ = 0.0f;
        x2_ = 0.0f;
        histX_.clear(static_cast<size_t>(poles_));
        histY_.clear(static_cast<size_t>(poles_));
    }

  private:
    void tick(float &real, float &imaginary, float input) {
        real = 0.0f;
        imaginary = 0.0f;
        x1_ = input;
        x2_ = input;

        if (!initialized_) {
            return;
        }

        const int bankPoles = poles_ / 2;
        for (int index = 0; index < bankPoles; ++index) {
            imaginary = coeffs_[static_cast<size_t>(index)] * (x1_ - histY_[static_cast<size_t>(index)]) +
                        histX_[static_cast<size_t>(index)];
            histX_[static_cast<size_t>(index)] = x1_;
            histY_[static_cast<size_t>(index)] = imaginary;
            x1_ = imaginary;
        }

        for (int index = bankPoles; index < poles_; ++index) {
            real = coeffs_[static_cast<size_t>(index)] * (x2_ - histY_[static_cast<size_t>(index)]) +
                   histX_[static_cast<size_t>(index)];
            histX_[static_cast<size_t>(index)] = x2_;
            histY_[static_cast<size_t>(index)] = real;
            x2_ = real;
        }
    }

    void calculateCoefficients(float sampleRate) {
        if (sampleRate == 0.0f) {
            return;
        }

        constexpr float pi = 3.14159265358979323846f;
        const float bandLow = 15.0f;
        const float bandHigh = sampleRate * 0.5f;
        const double bandRatio = bandLow / bandHigh;

        const double k = std::sqrt(1.0 - std::pow(bandRatio, 2.0));
        const double l = 0.5 * ((1.0 - std::sqrt(k)) / (1.0 + std::sqrt(k)));
        const double m = l + (2.0 * std::pow(l, 5.0)) + (15.0 * std::pow(l, 9.0));
        const double q = std::exp((std::pow(pi, 2.0)) / std::log(m));

        const int n = static_cast<int>(std::ceil(std::log(0.2 * pi / 720.0) / std::log(q)));
        poles_ = n % 2 == 0 ? n : n + 1;

        coeffs_.calloc(static_cast<size_t>(poles_));
        histX_.calloc(static_cast<size_t>(poles_));
        histY_.calloc(static_cast<size_t>(poles_));

        auto calcPole = [&](float x) {
            const double y = std::atan(((std::pow(q, 2.0) - std::pow(q, 6.0)) * std::sin(4.0 * x)) /
                                       (1.0 + (std::pow(q, 2.0) + std::pow(q, 6.0)) * std::cos(4.0 * x)));
            return std::tan(x - y);
        };
        auto calcCoeff = [&](float pole) {
            const float g = (bandLow * pi * pole) / sampleRate;
            return (g - 1.0f) / (g + 1.0f);
        };

        const float factor = pi / 4.0f / static_cast<float>(poles_);
        const float scale = 1.0f / std::sqrt(static_cast<float>(bandRatio));
        const int bankPoles = poles_ / 2;

        for (int index = 0; index < bankPoles; ++index) {
            const float r = 4.0f * (static_cast<float>(index) + 1.0f);
            const float poleA = scale * calcPole(factor * (r - 3.0f));
            const float poleB = scale * calcPole(factor * (r - 1.0f));
            coeffs_[static_cast<size_t>(index)] = calcCoeff(poleA);
            coeffs_[static_cast<size_t>(bankPoles + index)] = calcCoeff(poleB);
        }

        reset();
    }

    bool initialized_ = false;
    int poles_ = 0;
    juce::HeapBlock<float> coeffs_;
    juce::HeapBlock<float> histX_;
    juce::HeapBlock<float> histY_;
    float x1_ = 0.0f;
    float x2_ = 0.0f;
};

} // namespace dsp
} // namespace qs

namespace qs {
namespace decode {

enum class Channel { LF, RF, LB, RB };
enum class CtrlChannel { A, B };

struct FilterCoefficients {
    double b0 = 1.0;
    double b1 = 0.0;
    double b2 = 0.0;
    double a0 = 0.0;
    double a1 = 0.0;
    double a2 = 0.0;

    FilterCoefficients() = default;

    FilterCoefficients(double b0In, double b1In, double b2In, double a0In, double a1In, double a2In)
        : b0(b0In), b1(b1In), b2(b2In), a0(a0In), a1(a1In), a2(a2In) {}

    qs::dsp::Coefficients dspCoeffs() const { return {b0, b1, b2, a0, a1, a2}; }
};

struct BandSpec {
    float attackMS = 5.0f;
    float releaseMS = 5.0f;
    float lrWidthDB = 0.0f;
    float fbWidthDB = 0.0f;
    float gain = 1.0f;
    FilterCoefficients coeffs;
};

class Controller {
  public:
    Controller(qs::dsp::EnvelopeTiming timing, float widthDB) : envelope_(timing, 2), widthDB_(widthDB) {}

    void process(juce::AudioBuffer<float> &buffer) {
        const int numSamples = buffer.getNumSamples();
        auto *a = buffer.getWritePointer(static_cast<int>(CtrlChannel::A));
        auto *b = buffer.getWritePointer(static_cast<int>(CtrlChannel::B));

        if (widthDB_ <= 0.0f) {
            juce::FloatVectorOperations::fill(a, 0.5f, numSamples);
            juce::FloatVectorOperations::fill(b, 0.5f, numSamples);
            return;
        }

        envelope_.process(buffer);
        qs::dsp::log10Channels(buffer);
        juce::FloatVectorOperations::subtract(a, b, numSamples);
        juce::FloatVectorOperations::multiply(a, 20.0f, numSamples);
        juce::FloatVectorOperations::clip(a, a, -widthDB_, widthDB_, numSamples);
        juce::FloatVectorOperations::add(a, widthDB_, numSamples);
        juce::FloatVectorOperations::multiply(a, 0.5f / widthDB_, numSamples);
        juce::FloatVectorOperations::copy(b, a, numSamples);
        juce::FloatVectorOperations::add(b, -1.0f, numSamples);
        juce::FloatVectorOperations::abs(b, b, numSamples);
    }

    void prepare(float sampleRate) { envelope_.prepare(sampleRate); }

    void reset() { envelope_.reset(); }

  private:
    qs::dsp::Envelope envelope_;
    float widthDB_ = 0.0f;
};

class VariableMatrix {
  public:
    VariableMatrix(qs::dsp::EnvelopeTiming timing, float lrWidthDB, float fbWidthDB)
        : ctrlLR_(timing, lrWidthDB), ctrlFB_(timing, fbWidthDB) {
        bufferLR_.setSize(2, 256);
        bufferFB_.setSize(2, 256);
        bufferLR_.clear();
        bufferFB_.clear();
    }

    void prepare(float sampleRate, int samplesPerBlock) {
        bufferLR_.setSize(2, samplesPerBlock);
        bufferLR_.clear();
        bufferFB_.setSize(2, samplesPerBlock);
        bufferFB_.clear();
        ctrlLR_.prepare(sampleRate);
        ctrlFB_.prepare(sampleRate);
    }

    void reset() {
        bufferLR_.clear();
        bufferFB_.clear();
        ctrlLR_.reset();
        ctrlFB_.reset();
    }

    void process(juce::AudioBuffer<float> &buffer) {
        const int numSamples = buffer.getNumSamples();
        const int chanLF = static_cast<int>(Channel::LF);
        const int chanRF = static_cast<int>(Channel::RF);
        const int chanLB = static_cast<int>(Channel::LB);
        const int chanRB = static_cast<int>(Channel::RB);
        const int ctrlChanA = static_cast<int>(CtrlChannel::A);
        const int ctrlChanB = static_cast<int>(CtrlChannel::B);

        bufferLR_.copyFrom(ctrlChanA, 0, buffer, chanLF, 0, numSamples);
        bufferLR_.copyFrom(ctrlChanB, 0, buffer, chanRF, 0, numSamples);
        ctrlLR_.process(bufferLR_);

        bufferFB_.copyFrom(ctrlChanA, 0, buffer, chanLF, 0, numSamples);
        bufferFB_.addFrom(ctrlChanA, 0, buffer, chanRF, 0, numSamples);
        bufferFB_.copyFrom(ctrlChanB, 0, buffer, chanLF, 0, numSamples);
        bufferFB_.addFrom(ctrlChanB, 0, buffer, chanRF, 0, numSamples, -1.0f);
        ctrlFB_.process(bufferFB_);

        bufferLR_.applyGain(qs::dsp::root2);
        bufferFB_.applyGain(qs::dsp::root2);

        auto *leftFront = buffer.getWritePointer(chanLF);
        auto *rightFront = buffer.getWritePointer(chanRF);
        auto *leftBack = buffer.getWritePointer(chanLB);
        auto *rightBack = buffer.getWritePointer(chanRB);

        const auto *ctrlLeft = bufferLR_.getReadPointer(ctrlChanA);
        const auto *ctrlRight = bufferLR_.getReadPointer(ctrlChanB);
        const auto *ctrlFront = bufferFB_.getReadPointer(ctrlChanA);
        const auto *ctrlBack = bufferFB_.getReadPointer(ctrlChanB);

        for (int index = 0; index < numSamples; ++index) {
            const float lf = leftFront[index];
            const float rf = rightFront[index];
            const float lb = leftBack[index];
            const float rb = rightBack[index];
            const float cf = ctrlFront[index];
            const float cb = ctrlBack[index];
            const float cl = ctrlLeft[index];
            const float cr = ctrlRight[index];

            leftFront[index] = ((1.0f + cf) * (lf - rf)) + ((1.0f + cl) * qs::dsp::root2 * rf);
            rightFront[index] = (-(1.0f + cf) * (lf - rf)) + ((1.0f + cr) * qs::dsp::root2 * lf);
            leftBack[index] = ((1.0f + cb) * (lb + rb)) - ((1.0f + cl) * qs::dsp::root2 * rb);
            rightBack[index] = ((1.0f + cb) * (lb + rb)) - ((1.0f + cr) * qs::dsp::root2 * lb);
        }
    }

  private:
    Controller ctrlLR_;
    Controller ctrlFB_;
    juce::AudioBuffer<float> bufferLR_;
    juce::AudioBuffer<float> bufferFB_;
};

class BandDecoder {
  public:
    explicit BandDecoder(BandSpec spec)
        : filter_(spec.coeffs.dspCoeffs()),
          matrix_({spec.attackMS, spec.releaseMS}, spec.lrWidthDB, spec.fbWidthDB),
          gain_(spec.gain) {
        buffer_.setSize(4, 256);
    }

    void filterAndDecodeFrom(juce::AudioBuffer<float> &input) {
        buffer_.makeCopyOf(input, true);
        filter_.process(buffer_);
        matrix_.process(buffer_);
    }

    void addTo(juce::AudioBuffer<float> &output) {
        const int numChannels = buffer_.getNumChannels();
        const int numSamples = buffer_.getNumSamples();
        for (int channel = 0; channel < numChannels; ++channel) {
            output.addFrom(channel, 0, buffer_, channel, 0, numSamples, gain_);
        }
    }

    void prepare(float sampleRate, int samplesPerBlock) {
        buffer_.setSize(4, samplesPerBlock);
        buffer_.clear();
        filter_.prepare(sampleRate, buffer_.getNumChannels());
        matrix_.prepare(sampleRate, samplesPerBlock);
    }

    void reset() {
        buffer_.clear();
        filter_.reset();
        matrix_.reset();
    }

  private:
    juce::AudioBuffer<float> buffer_;
    qs::dsp::IIRFilter filter_;
    VariableMatrix matrix_;
    float gain_ = 1.0f;
};

class MultiBandDecoder {
  public:
    explicit MultiBandDecoder(std::vector<BandSpec> specs) {
        jassert(!specs.empty());
        bands_.reserve(specs.size());
        for (const auto &spec : specs) {
            bands_.push_back(std::make_unique<BandDecoder>(spec));
        }
    }

    void process(juce::AudioBuffer<float> &buffer) {
        const int chanLF = static_cast<int>(Channel::LF);
        const int chanRF = static_cast<int>(Channel::RF);
        const int chanLB = static_cast<int>(Channel::LB);
        const int chanRB = static_cast<int>(Channel::RB);

        hilbertL_.process(buffer, chanLF, chanLB, chanLF);
        hilbertR_.process(buffer, chanRF, chanRB, chanRF);

        for (auto &band : bands_) {
            band->filterAndDecodeFrom(buffer);
        }

        buffer.clear();
        for (auto &band : bands_) {
            band->addTo(buffer);
        }
    }

    void prepare(float sampleRate, int samplesPerBlock) {
        hilbertL_.prepare(sampleRate);
        hilbertR_.prepare(sampleRate);
        for (auto &band : bands_) {
            band->prepare(sampleRate, samplesPerBlock);
        }
    }

    void reset() {
        hilbertL_.reset();
        hilbertR_.reset();
        for (auto &band : bands_) {
            band->reset();
        }
    }

  private:
    qs::dsp::HilbertTransform hilbertL_;
    qs::dsp::HilbertTransform hilbertR_;
    std::vector<std::unique_ptr<BandDecoder>> bands_;
};

} // namespace decode
} // namespace qs

class QSDecoderFallback {
  public:
    explicit QSDecoderFallback(int32_t sampleRate)
        : sampleRate_(sampleRate),
          decoder_(std::vector<qs::decode::BandSpec>({
              {
                  20.0f,
                  20.0f,
                  10.0f,
                  10.0f,
                  0.5011872336272722f,
                  qs::decode::FilterCoefficients(0.061511768503621556, 0.061511768503621556, 0.0, 1.0,
                                                 -0.8769764629927568, 0.0),
              },
              {
                  20.0f,
                  20.0f,
                  10.0f,
                  10.0f,
                  0.5011872336272722f,
                  qs::decode::FilterCoefficients(0.9384882314963784, -0.9384882314963784, 0.0, 1.0,
                                                 -0.8769764629927568, 0.0),
              },
          })) {}

    void decode(const float *left,
                const float *right,
                uint32_t frameCount,
                float *frontLeft,
                float *frontRight,
                float *rearLeft,
                float *rearRight) {
        if (frameCount == 0) {
            return;
        }

        if (preparedFrames_ != static_cast<int>(frameCount)) {
            renderBuffer_.setSize(4, static_cast<int>(frameCount));
            decoder_.prepare(static_cast<float>(sampleRate_), static_cast<int>(frameCount));
            decoder_.reset();
            preparedFrames_ = static_cast<int>(frameCount);
        }

        std::copy_n(left, frameCount, renderBuffer_.getWritePointer(static_cast<int>(qs::decode::Channel::LF)));
        std::copy_n(right, frameCount, renderBuffer_.getWritePointer(static_cast<int>(qs::decode::Channel::RF)));
        renderBuffer_.clear(static_cast<int>(qs::decode::Channel::LB), 0, static_cast<int>(frameCount));
        renderBuffer_.clear(static_cast<int>(qs::decode::Channel::RB), 0, static_cast<int>(frameCount));

        decoder_.process(renderBuffer_);

        std::copy_n(renderBuffer_.getReadPointer(static_cast<int>(qs::decode::Channel::LF)), frameCount, frontLeft);
        std::copy_n(renderBuffer_.getReadPointer(static_cast<int>(qs::decode::Channel::RF)), frameCount, frontRight);
        std::copy_n(renderBuffer_.getReadPointer(static_cast<int>(qs::decode::Channel::LB)), frameCount, rearLeft);
        std::copy_n(renderBuffer_.getReadPointer(static_cast<int>(qs::decode::Channel::RB)), frameCount, rearRight);
    }

  private:
    int32_t sampleRate_;
    int preparedFrames_ = 0;
    juce::AudioBuffer<float> renderBuffer_;
    qs::decode::MultiBandDecoder decoder_;
};
