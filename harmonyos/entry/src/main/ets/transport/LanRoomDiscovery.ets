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
  static readonly BEACON_MAGIC = 'SUNSET_RIPPLE_BEACON';
  static readonly BROADCAST_INTERVAL_MS = 1000;
  static readonly ROOM_EXPIRY_MS = 3500;
}

/**
 * 鸿蒙端局域网扫描器：监听 UDP 8990 广播发现附近的落日后残波房间
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
          const parts = text.split('|');
          if (parts.length >= 5 && parts[0] === LanDiscoveryConfig.BEACON_MAGIC) {
            const roomName = parts[1];
            const hostIp = parts[2];
            const signalPort = parseInt(parts[3], 10);
            const memberCount = parseInt(parts[4], 10);
            const key = `${hostIp}:${signalPort}`;
            this.rooms.set(key, {
              roomName,
              hostIp,
              signalPort,
              memberCount,
              lastSeen: Date.now()
            });
            this.notify();
          }
        } catch (_) {}
      });

      this.isRunning = true;
    } catch (e) {
      hilog.error(0x0000, 'HarmonyLanScanner', `Bind scanner port failed: ${JSON.stringify(e)}`);
    }
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

