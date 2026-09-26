#!/usr/bin/env python3
"""Push docs/asc/LISTING.md + docs/asc/screenshots/*.png to App Store Connect.

App: AI Camera - Music Reader (Apple ID 6816476323, com.ragnus.vp), version 1.0, en-US.
Never submits for review.

Env: APP_STORE_CONNECT_KEY_ID, APP_STORE_CONNECT_ISSUER_ID, APP_STORE_CONNECT_API_KEY_P8
     (P8 contents; literal \\n accepted). Needs: pip install PyJWT cryptography requests
Flags: --no-screenshots  --dry-run
"""
from __future__ import annotations
import hashlib, os, re, sys, time
from pathlib import Path
import jwt, requests

HERE = Path(__file__).resolve().parent
APP_ID = "6816476323"
VERSION = "1.0"
LOCALE = "en-US"
SHOT_TYPES = {"iphone-69": "APP_IPHONE_67", "ipad-13": "APP_IPAD_PRO_3GEN_129"}
DRY = "--dry-run" in sys.argv
BASE = "https://api.appstoreconnect.apple.com"


def token() -> str:
    now = int(time.time())
    p8 = os.environ["APP_STORE_CONNECT_API_KEY_P8"].replace("\\n", "\n").strip()
    return jwt.encode({"iss": os.environ["APP_STORE_CONNECT_ISSUER_ID"].strip(), "iat": now,
                       "exp": now + 1100, "aud": "appstoreconnect-v1"}, p8, algorithm="ES256",
                      headers={"kid": os.environ["APP_STORE_CONNECT_KEY_ID"].strip()})


def api(method, path, body=None):
    if DRY and method != "GET":
        print("DRY", method, path, body if body and len(str(body)) < 400 else "")
        return {"data": {"id": "dry", "attributes": {}}}
    r = requests.request(method, path if path.startswith("http") else BASE + path, json=body,
                         headers={"Authorization": "Bearer " + token()}, timeout=120)
    if r.status_code >= 300:
        raise SystemExit(f"{method} {path} -> {r.status_code}: {r.text[:2000]}")
    return r.json() if r.text else {}


def listing() -> dict:
    md = (HERE / "LISTING.md").read_text()
    out = {}
    for m in re.finditer(r"^## ([^\n(]+?)(?: \(\d+.*?\))?\n```\n(.*?)```", md, re.S | re.M):
        out[m.group(1).strip()] = m.group(2).strip()
    return out


def url_ok(url: str) -> bool:
    if not url:
        return False
    try:
        r = requests.get(url, timeout=20)
        return r.status_code == 200 and "Music Reader" in r.text
    except requests.RequestException:
        return False


def check_limits(L):
    for k, lim in [("Name", 30), ("Subtitle", 30), ("Promotional text", 170), ("Keywords", 100), ("Description", 4000)]:
        assert len(L[k]) <= lim, f"{k} is {len(L[k])} > {lim}"
    blob = " ".join(L.values()).lower()
    assert "grok" not in blob, "listing must not mention Grok"


def main():
    L = listing()
    check_limits(L)
    support = L.get("Support URL", ""); privacy = L.get("Privacy Policy URL", ""); marketing = L.get("Marketing URL", "")
    support_ok, privacy_ok, marketing_ok = url_ok(support), url_ok(privacy), url_ok(marketing)
    print(f"support {support!r} live={support_ok}; privacy {privacy!r} live={privacy_ok}")

    # App info (name, subtitle, privacy URL) + categories
    infos = api("GET", f"/v1/apps/{APP_ID}/appInfos")["data"]
    info = next(i for i in infos if i["attributes"].get("appStoreState") != "READY_FOR_SALE")
    locs = api("GET", f"/v1/appInfos/{info['id']}/appInfoLocalizations")["data"]
    loc = next(l for l in locs if l["attributes"]["locale"] == LOCALE)
    attrs = {"name": L["Name"], "subtitle": L["Subtitle"]}
    if privacy_ok:
        attrs["privacyPolicyUrl"] = privacy
    api("PATCH", f"/v1/appInfoLocalizations/{loc['id']}", {"data": {"type": "appInfoLocalizations", "id": loc["id"], "attributes": attrs}})
    print("appInfoLocalization updated", list(attrs))
    api("PATCH", f"/v1/appInfos/{info['id']}", {"data": {"type": "appInfos", "id": info["id"], "relationships": {
        "primaryCategory": {"data": {"type": "appCategories", "id": "MUSIC"}},
        "secondaryCategory": {"data": {"type": "appCategories", "id": "EDUCATION"}}}}})
    print("categories MUSIC / EDUCATION")

    # Version 1.0 + en-US version localization
    vers = api("GET", f"/v1/apps/{APP_ID}/appStoreVersions?filter[platform]=IOS&filter[versionString]={VERSION}")["data"]
    if not vers:
        raise SystemExit(f"version {VERSION} not found")
    ver = vers[0]
    api("PATCH", f"/v1/appStoreVersions/{ver['id']}", {"data": {"type": "appStoreVersions", "id": ver["id"], "attributes": {"copyright": L["Copyright"]}}})
    vlocs = api("GET", f"/v1/appStoreVersions/{ver['id']}/appStoreVersionLocalizations")["data"]
    vattrs = {"description": L["Description"], "keywords": L["Keywords"], "promotionalText": L["Promotional text"]}
    if support_ok:
        vattrs["supportUrl"] = support
    if marketing_ok:
        vattrs["marketingUrl"] = marketing
    vloc = next((l for l in vlocs if l["attributes"]["locale"] == LOCALE), None)
    if vloc:
        api("PATCH", f"/v1/appStoreVersionLocalizations/{vloc['id']}", {"data": {"type": "appStoreVersionLocalizations", "id": vloc["id"], "attributes": vattrs}})
    else:
        vloc = api("POST", "/v1/appStoreVersionLocalizations", {"data": {"type": "appStoreVersionLocalizations", "attributes": {"locale": LOCALE, **vattrs},
                   "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": ver["id"]}}}}})["data"]
    print("appStoreVersionLocalization updated", list(vattrs))

    if "--no-screenshots" in sys.argv:
        return
    sets = api("GET", f"/v1/appStoreVersionLocalizations/{vloc['id']}/appScreenshotSets")["data"]
    for prefix, dtype in SHOT_TYPES.items():
        files = sorted((HERE / "screenshots").glob(f"{prefix}-*.png"))
        if not files:
            continue
        sset = next((s for s in sets if s["attributes"]["screenshotDisplayType"] == dtype), None)
        if sset is None:
            sset = api("POST", "/v1/appScreenshotSets", {"data": {"type": "appScreenshotSets", "attributes": {"screenshotDisplayType": dtype},
                       "relationships": {"appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": vloc["id"]}}}}})["data"]
        else:  # replace: delete what is there so the set mirrors the repo
            for old in api("GET", f"/v1/appScreenshotSets/{sset['id']}/appScreenshots")["data"]:
                api("DELETE", f"/v1/appScreenshots/{old['id']}")
        for f in files:
            data = f.read_bytes()
            shot = api("POST", "/v1/appScreenshots", {"data": {"type": "appScreenshots", "attributes": {"fileName": f.name, "fileSize": len(data)},
                       "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": sset["id"]}}}}})["data"]
            if DRY:
                continue
            for op in shot["attributes"]["uploadOperations"]:
                chunk = data[op["offset"]: op["offset"] + op["length"]]
                h = {x["name"]: x["value"] for x in op.get("requestHeaders", [])}
                r = requests.request(op["method"], op["url"], data=chunk, headers=h, timeout=180)
                r.raise_for_status()
            api("PATCH", f"/v1/appScreenshots/{shot['id']}", {"data": {"type": "appScreenshots", "id": shot["id"],
                "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})
            print("uploaded", dtype, f.name)
    # report delivery state
    time.sleep(5)
    for s in api("GET", f"/v1/appStoreVersionLocalizations/{vloc['id']}/appScreenshotSets")["data"]:
        for sc in api("GET", f"/v1/appScreenshotSets/{s['id']}/appScreenshots")["data"]:
            a = sc["attributes"]
            print("SHOT", s["attributes"]["screenshotDisplayType"], a.get("fileName"), (a.get("assetDeliveryState") or {}).get("state"))


if __name__ == "__main__":
    main()
