#!/usr/bin/env python3
"""Attach the review demo video (docs/asc/review-video.mp4) to the App Review
details of AI Camera - Music Reader, via POST /v1/appStoreReviewAttachments.

Idempotent: if an attachment with the same file name and MD5 checksum already
exists on the review detail, it is reported and nothing is uploaded.
Never creates or modifies a review submission.

Env: APP_STORE_CONNECT_KEY_ID, APP_STORE_CONNECT_ISSUER_ID,
     APP_STORE_CONNECT_API_KEY_P8, BUNDLE_ID (default com.ragnus.vp),
     VERSION_STRING (default 1.0).
"""
import hashlib, os, time
from pathlib import Path
import jwt, requests

BASE = "https://api.appstoreconnect.apple.com"
ROOT = Path(__file__).resolve().parents[2]
VIDEO = ROOT / "docs" / "asc" / "review-video.mp4"
_tok = {"v": None, "t": 0}


def token():
    now = int(time.time())
    if _tok["v"] and now - _tok["t"] < 600:
        return _tok["v"]
    p8 = os.environ["APP_STORE_CONNECT_API_KEY_P8"].replace("\\n", "\n").strip()
    _tok["v"] = jwt.encode({"iss": os.environ["APP_STORE_CONNECT_ISSUER_ID"].strip(), "iat": now,
                            "exp": now + 1100, "aud": "appstoreconnect-v1"}, p8, algorithm="ES256",
                           headers={"kid": os.environ["APP_STORE_CONNECT_KEY_ID"].strip()})
    _tok["t"] = now
    return _tok["v"]


def api(method, path, body=None):
    r = requests.request(method, path if path.startswith("http") else BASE + path, json=body,
                         headers={"Authorization": "Bearer " + token()}, timeout=180)
    if r.status_code >= 300:
        raise SystemExit(f"{method} {path} -> {r.status_code}: {r.text[:1500]}")
    return r.json() if r.text else {}


def main():
    bundle = os.environ.get("BUNDLE_ID", "com.ragnus.vp").strip()
    ver_str = os.environ.get("VERSION_STRING", "1.0").strip()
    data = VIDEO.read_bytes()
    md5 = hashlib.md5(data).hexdigest()
    app = api("GET", f"/v1/apps?filter[bundleId]={bundle}")["data"][0]
    ver = api("GET", f"/v1/apps/{app['id']}/appStoreVersions?filter[platform]=IOS&filter[versionString]={ver_str}")["data"][0]
    print("version", ver["id"], ver_str, ver["attributes"].get("appStoreState"))
    rd_id = api("GET", f"/v1/appStoreVersions/{ver['id']}/appStoreReviewDetail")["data"]["id"]

    cur = api("GET", f"/v1/appStoreReviewDetails/{rd_id}/appStoreReviewAttachments")
    for a in cur.get("data", []):
        at = a["attributes"]
        print("existing attachment:", a["id"], at.get("fileName"), (at.get("assetDeliveryState") or {}).get("state"))
        if at.get("fileName") == VIDEO.name and at.get("sourceFileChecksum") == md5:
            print("ATTACH_OK already present:", a["id"])
            return

    att = api("POST", "/v1/appStoreReviewAttachments", {"data": {"type": "appStoreReviewAttachments",
              "attributes": {"fileName": VIDEO.name, "fileSize": len(data)},
              "relationships": {"appStoreReviewDetail": {"data": {"type": "appStoreReviewDetails", "id": rd_id}}}}})["data"]
    for op in att["attributes"]["uploadOperations"]:
        chunk = data[op["offset"]: op["offset"] + op["length"]]
        h = {x["name"]: x["value"] for x in op.get("requestHeaders", [])}
        requests.request(op["method"], op["url"], data=chunk, headers=h, timeout=300).raise_for_status()
    api("PATCH", f"/v1/appStoreReviewAttachments/{att['id']}", {"data": {"type": "appStoreReviewAttachments",
        "id": att["id"], "attributes": {"uploaded": True, "sourceFileChecksum": md5}}})
    state = None
    for _ in range(60):
        st = api("GET", f"/v1/appStoreReviewAttachments/{att['id']}")["data"]["attributes"]
        state = (st.get("assetDeliveryState") or {}).get("state")
        if state in ("COMPLETE", "FAILED"):
            break
        time.sleep(5)
    print("ATTACHMENT", att["id"], VIDEO.name, len(data), "bytes md5", md5, "->", state)
    if state != "COMPLETE":
        raise SystemExit(f"attachment delivery state {state}")
    print("ATTACH_OK", att["id"])


if __name__ == "__main__":
    main()
