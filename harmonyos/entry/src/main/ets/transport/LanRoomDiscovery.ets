import socket from '@ohos.net.socket';
import hilog from '@ohos.hilog';

export interface LanDiscoveredRoom {
  roomName: string;
  hostIp: string;
  signalPort: number;
  memberCount: number;
  lastSeen: number;
}

export class LanDiscoveryConfig {
  static readonly DISCOVERY_PORT = 8990;
  // 必须与 Dart 侧 LanRoomDiscovery.magicHeader 完全一致，否则彼此收不到广播。
  static readonly DISCOVERY_MAGIC = 'SUNSET_RIPPLE_DISCOVERY_V1';
  static readonly BROADCAST_INTERVAL_MS = 1000;
  static readonly ROOM_EXPIRY_MS = 3500;
  static readonly MAX_TEXT_LENGTH = 64;
}

/**
 * 鸿蒙端局域网扫描器：监听 UDP 8990 广播发现附近的落日后残波房间。
 *
 * 广播载荷与 Dart 端 LanRoomDiscovery 完全一致——UTF-8 JSON：
 * { magic, roomId, roomName, hostNickname, port, members, action?, timestamp }
 * 房主 IP 取自数据报的源地址（载荷里不含 IP，防止伪造）。
 */
export class HarmonyLanScanner {
  private udp: socket.UDPSocket | null = null;
  private isRunning: boolean = false;
  private rooms: Map<string, LanDiscoveredRoom> = new Map();
  public onRoomsUpdate: (rooms: LanDiscoveredRoom[]) => void = () => {};

  async start(): Promise<void> {
    if (this.isRunning) return;
    try {
      this.udp = socket.constructUDPSocketInstance();
      await this.udp.bind({
        address: { address: '0.0.0.0', port: LanDiscoveryConfig.DISCOVERY_PORT, family: 1 }
      });

      this.udp.on('message', (value: socket.SocketMessageInfo) => {
        try {
          const text = new TextDecoder().decode(value.message);
          const json = JSON.parse(text) as Record<string, Object>;
          if (json.magic !== LanDiscoveryConfig.DISCOVERY_MAGIC) return;

          const roomId = json.roomId as string;
          if (!roomId) return;

          const key = `${roomId}`;

          // 收到解散通知，即刻移除，无需等待超时。广播谁都能发，只有与该房间
          // 最后一次广播同源的解散包才算数——否则同网段任何设备都能把别人
          // 列表里的房间踢掉。判定与 Dart 端 LanRoomDiscovery 保持一致。
          if ((json.action as string) === 'ROOM_CLOSED') {
            const known = this.rooms.get(key);
            const sourceIp = value.remoteInfo?.address ?? '';
            if (known && known.hostIp === sourceIp && this.rooms.delete(key)) {
              this.notify();
            }
            return;
          }

          const signalPort = Number(json.port);
          if (!Number.isFinite(signalPort) || signalPort <= 0 || signalPort > 65535) return;

          const hostIp = value.remoteInfo?.address ?? '';
          this.rooms.set(key, {
            roomName: HarmonyLanScanner.clampText(json.roomName as string),
            hostIp,
            signalPort,
            memberCount: Number(json.members) || 0,
            lastSeen: Date.now()
          });
          this.notify();
        } catch (_) {}
      });

      this.isRunning = true;
    } catch (e) {
      hilog.error(0x0000, 'HarmonyLanScanner', `Bind scanner port failed: ${JSON.stringify(e)}`);
    }
  }

  private static clampText(raw: string): string {
    if (!raw) return '';
    const trimmed = raw.trim();
    return trimmed.length <= LanDiscoveryConfig.MAX_TEXT_LENGTH
      ? trimmed
      : trimmed.substring(0, LanDiscoveryConfig.MAX_TEXT_LENGTH);
  }

  private notify(): void {
    const list: LanDiscoveredRoom[] = [];
    const now = Date.now();
    this.rooms.forEach((val, key) => {
      if (now - val.lastSeen <= LanDiscoveryConfig.ROOM_EXPIRY_MS) {
        list.push(val);
      } else {
        this.rooms.delete(key);
      }
    });
    this.onRoomsUpdate(list);
  }

  async stop(): Promise<void> {
    this.isRunning = false;
    if (this.udp) {
      this.udp.off('message');
      await this.udp.close();
      this.udp = null;
    }
    this.rooms.clear();
  }
}
