import audio from '@ohos.multimedia.audio';
import hilog from '@ohos.hilog';

/**
 * 鸿蒙原生通话级低延时音频引擎：
 * 采用 SOURCE_TYPE_VOICE_COMMUNICATION 与 STREAM_USAGE_VOICE_COMMUNICATION，
 * 自动激活系统级 AEC（硬件回声消除）与 NS（环境降噪）。
 */
export class HarmonyAudioEngine {
  private static readonly TAG = 'HarmonyAudioEngine';
  public static readonly SAMPLE_RATE = 16000;
  public static readonly FRAME_SAMPLES = 320; // 20ms

  private capturer: audio.AudioCapturer | null = null;
  private renderer: audio.AudioRenderer | null = null;
  private isRunning: boolean = false;
  public micMuted: boolean = false;
  public onPcmFrame: (pcm: Int16Array) => void = () => {};

  async start(): Promise<void> {
    if (this.isRunning) return;

    try {
      const audioStreamInfo: audio.AudioStreamInfo = {
        samplingRate: audio.AudioSamplingRate.SAMPLE_RATE_16000,
        channels: audio.AudioChannel.CHANNEL_1,
        sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
        encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW
      };

      // 1. 采集器配置（通话级回声消除模式）
      const capturerInfo: audio.AudioCapturerInfo = {
        source: audio.SourceType.SOURCE_TYPE_VOICE_COMMUNICATION,
        capturerFlags: 0
      };

      this.capturer = await audio.createAudioCapturer({
        streamInfo: audioStreamInfo,
        capturerInfo: capturerInfo
      });

      // 2. 渲染器配置（通话级流媒体输出）
      const rendererInfo: audio.AudioRendererInfo = {
        usage: audio.StreamUsage.STREAM_USAGE_VOICE_COMMUNICATION,
        rendererFlags: 0
      };

      this.renderer = await audio.createAudioRenderer({
        streamInfo: audioStreamInfo,
        rendererInfo: rendererInfo
      });

      await this.capturer.start();
      await this.renderer.start();
      this.isRunning = true;

      // 启动异步采集循环
      this.captureLoop();
      hilog.info(0x0000, HarmonyAudioEngine.TAG, 'AudioEngine started successfully with hardware AEC');
    } catch (err) {
      hilog.error(0x0000, HarmonyAudioEngine.TAG, `Failed to start AudioEngine: ${JSON.stringify(err)}`);
      await this.stop();
      throw err;
    }
  }

  private async captureLoop(): Promise<void> {
    const bufferBytes = HarmonyAudioEngine.FRAME_SAMPLES * 2; // 640 字节
    while (this.isRunning && this.capturer) {
      try {
        const buffer = await this.capturer.read(bufferBytes, true);
        if (buffer && buffer.byteLength > 0 && !this.micMuted) {
          const pcm = new Int16Array(buffer);
          this.onPcmFrame(pcm);
        }
      } catch (e) {
        if (!this.isRunning) break;
        hilog.warn(0x0000, HarmonyAudioEngine.TAG, `Read audio error: ${JSON.stringify(e)}`);
      }
    }
  }

  playPcm(pcm: Int16Array): void {
    if (this.renderer && this.isRunning) {
      try {
        this.renderer.write(pcm.buffer);
      } catch (e) {
        hilog.warn(0x0000, HarmonyAudioEngine.TAG, `Play audio error: ${JSON.stringify(e)}`);
      }
    }
  }

  async stop(): Promise<void> {
    this.isRunning = false;
    if (this.capturer) {
      try {
        await this.capturer.stop();
        await this.capturer.release();
      } catch (_) {}
      this.capturer = null;
    }
    if (this.renderer) {
      try {
        await this.renderer.stop();
        await this.renderer.release();
      } catch (_) {}
      this.renderer = null;
    }
  }
}

