"""Israeli Transverse Mercator (EPSG:2039) to WGS84 lon/lat, without pyproj: the inverse
projection on GRS80, then Israel 1993 -> WGS84 by the 7-parameter Helmert shift EPSG uses."""
import math

A, F = 6378137.0, 1 / 298.257222101            # GRS80
K0, LAT0, LON0 = 1.0000067, math.radians(31 + 44 / 60 + 3.817921 / 3600), math.radians(35 + 12 / 60 + 16.261 / 3600)
FE, FN = 219529.584, 626907.390
TOWGS = (-24.0024, -17.1032, -17.8444, -0.33077, -1.85269, 1.66969, 5.4248)   # m, arc-s, ppm


def _m(phi, e2):
    e4, e6 = e2 * e2, e2 ** 3
    return A * ((1 - e2 / 4 - 3 * e4 / 64 - 5 * e6 / 256) * phi - (3 * e2 / 8 + 3 * e4 / 32 + 45 * e6 / 1024) * math.sin(2 * phi)
                + (15 * e4 / 256 + 45 * e6 / 1024) * math.sin(4 * phi) - (35 * e6 / 3072) * math.sin(6 * phi))


def _tm_inverse(x, y):
    e2 = F * (2 - F)
    ep2 = e2 / (1 - e2)
    m = _m(LAT0, e2) + (y - FN) / K0
    mu = m / (A * (1 - e2 / 4 - 3 * e2 ** 2 / 64 - 5 * e2 ** 3 / 256))
    e1 = (1 - math.sqrt(1 - e2)) / (1 + math.sqrt(1 - e2))
    phi1 = (mu + (3 * e1 / 2 - 27 * e1 ** 3 / 32) * math.sin(2 * mu) + (21 * e1 ** 2 / 16 - 55 * e1 ** 4 / 32) * math.sin(4 * mu)
            + (151 * e1 ** 3 / 96) * math.sin(6 * mu) + (1097 * e1 ** 4 / 512) * math.sin(8 * mu))
    c1, t1 = ep2 * math.cos(phi1) ** 2, math.tan(phi1) ** 2
    n1 = A / math.sqrt(1 - e2 * math.sin(phi1) ** 2)
    r1 = A * (1 - e2) / (1 - e2 * math.sin(phi1) ** 2) ** 1.5
    d = (x - FE) / (n1 * K0)
    lat = phi1 - (n1 * math.tan(phi1) / r1) * (d * d / 2 - (5 + 3 * t1 + 10 * c1 - 4 * c1 * c1 - 9 * ep2) * d ** 4 / 24
                                              + (61 + 90 * t1 + 298 * c1 + 45 * t1 * t1 - 252 * ep2 - 3 * c1 * c1) * d ** 6 / 720)
    lon = LON0 + (d - (1 + 2 * t1 + c1) * d ** 3 / 6 + (5 - 2 * c1 + 28 * t1 - 3 * c1 * c1 + 8 * ep2 + 24 * t1 * t1) * d ** 5 / 120) / math.cos(phi1)
    return lat, lon


def _helmert(lat, lon):
    e2 = F * (2 - F)
    n = A / math.sqrt(1 - e2 * math.sin(lat) ** 2)
    X, Y, Z = n * math.cos(lat) * math.cos(lon), n * math.cos(lat) * math.sin(lon), n * (1 - e2) * math.sin(lat)
    tx, ty, tz, rx, ry, rz, s = TOWGS
    rx, ry, rz = (math.radians(v / 3600) for v in (rx, ry, rz))
    s = 1 + s * 1e-6
    # (position vector convention, as EPSG:1073 / proj's towgs84)
    X2 = tx + s * (X - rz * Y + ry * Z)
    Y2 = ty + s * (rz * X + Y - rx * Z)
    Z2 = tz + s * (-ry * X + rx * Y + Z)
    a, e2w = 6378137.0, 0.00669437999014    # WGS84
    p = math.hypot(X2, Y2)
    lat2 = math.atan2(Z2, p * (1 - e2w))
    for _ in range(6):
        nn = a / math.sqrt(1 - e2w * math.sin(lat2) ** 2)
        lat2 = math.atan2(Z2 + e2w * nn * math.sin(lat2), p)
    return lat2, math.atan2(Y2, X2)


def to_lonlat(x, y):
    lat, lon = _helmert(*_tm_inverse(x, y))
    return math.degrees(lon), math.degrees(lat)
