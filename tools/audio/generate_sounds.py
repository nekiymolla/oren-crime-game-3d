#!/usr/bin/env python3
"""Синтезирует звуки игры в assets/sounds/*.wav (ТЗ, раздел 22).

Своих сэмплов у проекта нет, а чужие — это лицензии и зависимость от
сети. Здесь всё собирается из шума, синусов и огибающих: звучит как
ретро-игра, но без лицензионных вопросов. Детерминированно (фиксированный
seed) — повторный запуск даёт те же файлы. Любой файл можно заменить
настоящим сэмплом с тем же именем — код игры не меняется.

Только стандартная библиотека Python (numpy на машине нет).

Использование: python3 tools/audio/generate_sounds.py
"""

import math
import os
import random
import struct
import wave

SR = 22050
OUT = os.path.join(os.path.dirname(__file__), '..', '..', 'assets', 'sounds')
rng = random.Random(20261015)


def silence(seconds):
    return [0.0] * int(SR * seconds)


def noise(n):
    return [rng.uniform(-1.0, 1.0) for _ in range(n)]


def lowpass(x, cutoff):
    a = 1.0 - math.exp(-2 * math.pi * cutoff / SR)
    y, out = 0.0, []
    for s in x:
        y += a * (s - y)
        out.append(y)
    return out


def highpass(x, cutoff):
    low = lowpass(x, cutoff)
    return [s - l for s, l in zip(x, low)]


def bandpass(x, low, high):
    return lowpass(highpass(x, low), high)


def env_exp(n, tau, delay=0.0):
    d = int(delay * SR)
    return [0.0 if i < d else math.exp(-(i - d) / (tau * SR)) for i in range(n)]


def mul(a, b):
    return [x * y for x, y in zip(a, b)]


def mix(*tracks):
    n = max(len(t) for t in tracks)
    out = [0.0] * n
    for t in tracks:
        for i, s in enumerate(t):
            out[i] += s
    return out


def scale(x, k):
    return [s * k for s in x]


def sweep_sine(n, f0, f1, harmonics=((1, 1.0),)):
    out, phase = [], 0.0
    for i in range(n):
        f = f0 + (f1 - f0) * i / max(1, n - 1)
        phase += 2 * math.pi * f / SR
        out.append(sum(a * math.sin(h * phase) for h, a in harmonics))
    return out


def sine(n, f, harmonics=((1, 1.0),)):
    return sweep_sine(n, f, f, harmonics)


def crossfade_loop(x, fade_seconds):
    """Бесшовная петля: хвост плавно перетекает в начало."""
    f = int(fade_seconds * SR)
    body = x[: len(x) - f]
    tail = x[len(x) - f :]
    for i in range(f):
        t = i / f
        body[i] = body[i] * t + tail[i] * (1 - t)
    return body


def normalize(x, peak=0.89):
    m = max(abs(s) for s in x) or 1.0
    return [s * peak / m for s in x]


def fade_out(x, seconds):
    f = int(seconds * SR)
    n = len(x)
    return [s * (min(1.0, (n - i) / f) if n - i < f else 1.0) for i, s in enumerate(x)]


def write(name, x, peak=0.89):
    x = normalize(x, peak)
    path = os.path.join(OUT, name + '.wav')
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b''.join(struct.pack('<h', int(max(-1.0, min(1.0, s)) * 32767)) for s in x))
    print(f'{name}.wav  {len(x) / SR:.2f} с')


# --- Оружие -----------------------------------------------------------------

def gunshot():
    n = int(0.7 * SR)
    crack = mul(highpass(noise(n), 1200), env_exp(n, 0.012))
    body = mul(lowpass(noise(n), 1800), env_exp(n, 0.05))
    thump = mul(sweep_sine(n, 110, 45), env_exp(n, 0.07))
    tail = mul(lowpass(noise(n), 600), env_exp(n, 0.22, delay=0.02))  # эхо улицы
    return fade_out(mix(scale(crack, 1.0), scale(body, 0.8), scale(thump, 1.1), scale(tail, 0.35)), 0.1)


def bullet_impact():
    n = int(0.18 * SR)
    click = mul(highpass(noise(n), 2500), env_exp(n, 0.008))
    ring = mul(sweep_sine(n, 2900, 2300, ((1, 1.0), (2.7, 0.3))), env_exp(n, 0.04))
    return mix(click, scale(ring, 0.35))


def metal_click(n, f1, f2, tau=0.025):
    return mix(scale(mul(highpass(noise(n), 3000), env_exp(n, 0.004)), 0.8),
               scale(mul(sine(n, f1), env_exp(n, tau)), 0.5),
               scale(mul(sine(n, f2), env_exp(n, tau * 0.7)), 0.3))


def reload():
    out = silence(0.6)
    for start, f1, f2 in ((0.0, 1800, 3100), (0.38, 1500, 2600)):
        click = metal_click(int(0.12 * SR), f1, f2)
        s = int(start * SR)
        for i, v in enumerate(click):
            out[s + i] += v
    return out


# --- Машины ----------------------------------------------------------------

def engine_loop():
    """Холостые ~40 Гц (4 цилиндра, 1200 об/мин), ровно 1 с — целое число
    периодов, петля бесшовна. Обороты игра задаёт скоростью воспроизведения."""
    n = SR
    out = []
    for i in range(n):
        t = i / SR
        p = 2 * math.pi * 40 * t
        pulse = sum(math.sin(h * p) / h ** 0.8 for h in range(1, 12))  # пилообразный рокот
        wobble = 1.0 + 0.15 * math.sin(2 * math.pi * 8 * t)            # неровность вспышек
        out.append(pulse * wobble)
    grit = lowpass(noise(n), 900)
    return lowpass(mix(out, scale(grit, 1.5)), 1600)


def tire_screech_loop():
    n = int(1.15 * SR)  # +0.15 с на перекрёстное затухание шва -> петля 1 с
    out, phase = [], 0.0
    for i in range(n):
        t = i / SR
        f = 2350 + 180 * math.sin(2 * math.pi * 6 * t) + 60 * math.sin(2 * math.pi * 17 * t)
        phase += 2 * math.pi * f / SR
        out.append(math.sin(phase) + 0.4 * math.sin(2 * phase))
    hiss = bandpass(noise(n), 1500, 5000)
    return crossfade_loop(mix(scale(out, 0.6), scale(hiss, 0.5)), 0.15)


def crash():
    n = int(1.0 * SR)
    bang = mul(lowpass(noise(n), 2500), env_exp(n, 0.06))
    low = mul(sweep_sine(n, 80, 40), env_exp(n, 0.12))
    clang = mix(*[scale(mul(sine(n, f), env_exp(n, tau)), a)
                  for f, tau, a in ((340, 0.35, 0.5), (517, 0.28, 0.4), (781, 0.22, 0.35), (1133, 0.15, 0.3), (1789, 0.1, 0.2))])
    glass = mul(highpass(noise(n), 4000), env_exp(n, 0.09, delay=0.03))
    return fade_out(mix(scale(bang, 1.0), scale(low, 0.8), scale(clang, 0.6), scale(glass, 0.3)), 0.2)


def siren_loop():
    """Вой (wail) 650 <-> 1350 Гц, период 2 с, петля 4 с. Базовая частота
    подогнана так, что за петлю набирается целое число периодов — фаза
    на шве совпадает."""
    n = 4 * SR

    def freq(t):
        return 1000 + 350 * math.sin(2 * math.pi * t / 2.0 - math.pi / 2)

    total = sum(freq(i / SR) for i in range(n)) / SR
    k = round(total) / total
    out, phase = [], 0.0
    for i in range(n):
        phase += 2 * math.pi * freq(i / SR) * k / SR
        # Нечётные гармоники — "квадратная" резкость динамика сирены.
        out.append(math.sin(phase) + 0.33 * math.sin(3 * phase) + 0.18 * math.sin(5 * phase))
    return lowpass(out, 4500)


def footstep():
    n = int(0.14 * SR)
    thud = mul(sweep_sine(n, 140, 70), env_exp(n, 0.025))
    scuff = mul(bandpass(noise(n), 300, 2500), env_exp(n, 0.02))
    return mix(scale(thud, 0.9), scale(scuff, 0.6))


# --- Погода и город ---------------------------------------------------------

def rain_loop():
    n = 5 * SR
    bed = bandpass(noise(n), 400, 5000)
    drops = [0.0] * n
    for _ in range(900):
        s = rng.randrange(n - 400)
        a = rng.uniform(0.2, 1.0)
        for i in range(300):
            drops[s + i] += a * rng.uniform(-1, 1) * math.exp(-i / 40)
    return crossfade_loop(mix(scale(bed, 0.7), scale(highpass(drops, 1500), 0.4)), 0.5)


def wind_loop():
    n = 7 * SR
    base = lowpass(noise(n), 500)
    out = []
    for i, s in enumerate(base):
        t = i / SR
        gust = 0.55 + 0.45 * math.sin(2 * math.pi * t / 3.5) * math.sin(2 * math.pi * t / 7.0 + 1.0)
        out.append(s * gust)
    whistle = mul(bandpass(noise(n), 700, 1100), [0.3 + 0.3 * math.sin(2 * math.pi * i / SR / 2.3) for i in range(n)])
    return crossfade_loop(mix(out, scale(whistle, 0.5)), 1.0)


def thunder():
    n = int(4.5 * SR)
    rumble = lowpass(lowpass(noise(n), 160), 160)
    envelope = []
    for i in range(n):
        t = i / SR
        roll = 0.6 + 0.4 * math.sin(2 * math.pi * t * 1.3) * math.sin(2 * math.pi * t * 0.55)
        envelope.append(min(1.0, t / 0.03) * math.exp(-t / 1.4) * roll)
    crack = mul(lowpass(noise(n), 1500), env_exp(n, 0.08))
    return fade_out(mix(mul(rumble, envelope), scale(crack, 0.25)), 0.5)


def city_loop():
    n = 8 * SR
    hum = lowpass(lowpass(noise(n), 250), 250)
    traffic = mul(bandpass(noise(n), 200, 900),
                  [0.5 + 0.5 * math.sin(2 * math.pi * i / SR / 4.0) ** 2 for i in range(n)])
    mains = sine(n, 100)
    return crossfade_loop(mix(scale(hum, 1.0), scale(traffic, 0.35), scale(mains, 0.03)), 1.0)


# --- Интерфейс --------------------------------------------------------------

def bell(n, f, tau):
    return mul(sine(n, f, ((1, 1.0), (2, 0.3), (3, 0.12))), env_exp(n, tau))


def pickup():
    n = int(0.45 * SR)
    a = bell(n, 1318.5, 0.08)                              # E6
    b = [0.0] * int(0.07 * SR) + bell(n, 1760.0, 0.15)     # A6
    return mix(a, b)


def purchase():
    out = silence(1.0)
    for k, f in enumerate((523.25, 659.25, 783.99, 1046.5)):   # C-E-G-C
        note = bell(int(0.6 * SR), f, 0.18)
        s = int(k * 0.09 * SR)
        for i, v in enumerate(note):
            if s + i < len(out):
                out[s + i] += v
    return fade_out(out, 0.2)


def hurt():
    n = int(0.25 * SR)
    thump = mul(sweep_sine(n, 90, 50), env_exp(n, 0.05))
    smack = mul(lowpass(noise(n), 1200), env_exp(n, 0.015))
    return mix(thump, scale(smack, 0.7))


def wasted():
    n = int(2.2 * SR)
    tone = mul(sweep_sine(n, 220, 55, ((1, 1.0), (2, 0.4), (3, 0.2))), [min(1.0, i / (0.05 * SR)) * math.exp(-i / (1.0 * SR)) for i in range(n)])
    swell = mul(lowpass(noise(n), 400), [math.sin(math.pi * i / n) for i in range(n)])
    return fade_out(mix(tone, scale(swell, 0.4)), 0.4)


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    write('gunshot', gunshot())
    write('bullet_impact', bullet_impact(), peak=0.6)
    write('reload', reload(), peak=0.7)
    write('engine_loop', engine_loop(), peak=0.7)
    write('tire_screech_loop', tire_screech_loop(), peak=0.5)
    write('crash', crash())
    write('siren_loop', siren_loop(), peak=0.7)
    write('footstep', footstep(), peak=0.5)
    write('rain_loop', rain_loop(), peak=0.6)
    write('wind_loop', wind_loop(), peak=0.6)
    write('thunder', thunder())
    write('city_loop', city_loop(), peak=0.5)
    write('pickup', pickup(), peak=0.6)
    write('purchase', purchase(), peak=0.6)
    write('hurt', hurt(), peak=0.8)
    write('wasted', wasted(), peak=0.8)
