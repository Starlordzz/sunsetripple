import { HarmonyAudioEngine } from '../audio/HarmonyAudioEngine';
import { Frame, FrameType } from '../model/Frame';

export interface MemberState {
  id: number;
  nickname: string;
  speaking: boolean;
  isSelf: boolean;
}

/**
 * 鸿蒙原生房间会话管理器：协调 AudioEngine、PTT 按键状态与网络收发
 */
export class HarmonyRoomSession {
  private audioEngine: HarmonyAudioEngine = new HarmonyAudioEngine();
  public selfNickname: string;
  public members: MemberState[] = [];
  public isConnected: boolean = false;
  public pttPressed: boolean = false;
  public micMuted: boolean = false;
  public isSpeakerOn: boolean = true;
  public onStateChanged: () => void = () => {};

  constructor(nickname: string) {
    this.selfNickname = nickname;
    this.audioEngine.onPcmFrame = (pcm: Int16Array) => {
      this.onLocalAudioCaptured(pcm);
    };
  }

  async start(): Promise<void> {
    await this.audioEngine.start();
    this.isConnected = true;
    this.members = [
      { id: 0, nickname: this.selfNickname, speaking: false, isSelf: true }
    ];
    this.onStateChanged();
  }

  setPttPressed(pressed: boolean): void {
    this.pttPressed = pressed;
    this.audioEngine.micMuted = !pressed;
    this.onStateChanged();
  }

  toggleMute(): void {
    this.micMuted = !this.micMuted;
    this.audioEngine.micMuted = this.micMuted;
    this.onStateChanged();
  }

  private onLocalAudioCaptured(pcm: Int16Array): void {
    // 录音 PCM 帧回调（可在此打包 Frame 并通过 UDP 发送）
  }

  async leave(): Promise<void> {
    this.isConnected = false;
    await this.audioEngine.stop();
    this.members = [];
    this.onStateChanged();
  }
}

