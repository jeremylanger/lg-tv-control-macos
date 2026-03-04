# Govee LAN API Reference

## Prerequisites

- Enable "LAN Control" in the Govee phone app under the device's settings (one-time setup)

## Network Architecture

- **Discovery multicast address:** `239.255.255.250`
- **Discovery port (send to):** `4001`
- **Discovery response port (listen on):** `4002`
- **Control command port:** `4003`
- **Protocol:** UDP

## Device Discovery

### Request Scan

Send UDP multicast to `239.255.255.250:4001`:

```json
{
    "msg": {
        "cmd": "scan",
        "data": {
            "account_topic": "reserve"
        }
    }
}
```

The `account_topic` field must be `"reserve"`.

### Response Scan

Listen on UDP port `4002` for response:

```json
{
    "msg": {
        "cmd": "scan",
        "data": {
            "ip": "192.168.1.23",
            "device": "1F:80:C5:32:32:36:72:4E",
            "sku": "Hxxxx",
            "bleVersionHard": "3.01.01",
            "bleVersionSoft": "1.03.01",
            "wifiVersionHard": "1.00.10",
            "wifiVersionSoft": "1.02.03"
        }
    }
}
```

**Response fields:**
- `ip` - Local IPv4 address for sending control commands
- `device` - Unique device identifier
- `sku` - Device model number (e.g., H6167)
- `bleVersionHard/Soft` - Bluetooth hardware/software versions
- `wifiVersionHard/Soft` - Wi-Fi hardware/software versions

## Control Commands

Send UDP to the device's IP on port `4003`.

### On/Off

```json
{
    "msg": {
        "cmd": "turn",
        "data": {
            "value": 1
        }
    }
}
```

- `value: 1` = **on**
- `value: 0` = **off**

### Brightness

```json
{
    "msg": {
        "cmd": "brightness",
        "data": {
            "value": 20
        }
    }
}
```

- `value` range: `1` to `100`

### Device Status Query

```json
{
    "msg": {
        "cmd": "devStatus",
        "data": {}
    }
}
```

**Response** (received on port `4002`):

```json
{
    "msg": {
        "cmd": "devStatus",
        "data": {
            "onOff": 1,
            "brightness": 100,
            "color": {
                "r": 255,
                "g": 0,
                "b": 0
            },
            "colorTemInKelvin": 7200
        }
    }
}
```

- `onOff` - `1` = on, `0` = off
- `brightness` - 1 to 100
- `color` - RGB values, 0 to 255 each
- `colorTemInKelvin` - 2000 to 9000

### Color / Color Temperature Control

```json
{
    "msg": {
        "cmd": "colorwc",
        "data": {
            "color": {
                "r": 0,
                "g": 12,
                "b": 8
            },
            "colorTemInKelvin": 7200
        }
    }
}
```

- When `colorTemInKelvin` is **not** `0`, the device converts the color temperature into RGB values (ignores the `color` field)
- When `colorTemInKelvin` is `0`, the device uses the `r`, `g`, `b` values from the `color` field
