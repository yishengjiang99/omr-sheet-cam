#!/usr/bin/env python3
"""Submit the Music Reader Pro subscriptions so they ride with the next app version review.

First-time subscriptions must be reviewed together with an app version: this POSTs
/v1/subscriptionSubmissions for each product (READY_TO_SUBMIT only) and is meant to run right
before the version's reviewSubmission is submitted (asc-submit-app-store.yml, input
submit_subscriptions). Products already WAITING_FOR_REVIEW / IN_REVIEW / APPROVED are skipped.
Exits 1 if a product is in any other state (e.g. MISSING_METADATA) so the version is not
submitted with a paywall that cannot load products.
Env: APP_STORE_CONNECT_KEY_ID, APP_STORE_CONNECT_ISSUER_ID, APP_STORE_CONNECT_API_KEY_P8, BUNDLE_ID
"""
from __future__ import annotations
import os, sys, time
import jwt, requests

BASE = "https://api.appstoreconnect.apple.com"
BUNDLE_ID = os.environ.get("BUNDLE_ID", "com.ragnus.vp").strip()
PRODUCT_IDS = ["com.ragnus.vp.pro.yearly", "com.ragnus.vp.pro.monthly"]
DONE = {"WAITING_FOR_REVIEW", "IN_REVIEW", "APPROVED"}


def token():
    now = int(time.time())
    p8 = os.environ["APP_STORE_CONNECT_API_KEY_P8"].replace("\\n", "\n").strip()
    return jwt.encode({"iss": os.environ["APP_STORE_CONNECT_ISSUER_ID"].strip(), "iat": now, "exp": now + 1100,
                       "aud": "appstoreconnect-v1"}, p8, algorithm="ES256",
                      headers={"kid": os.environ["APP_STORE_CONNECT_KEY_ID"].strip()})


def api(method, path, body=None):
    r = requests.request(method, path if path.startswith("http") else BASE + path, json=body,
                         headers={"Authorization": "Bearer " + token()}, timeout=90)
    return r.status_code, (r.json() if r.text else {})


def main():
    st, apps = api("GET", f"/v1/apps?filter[bundleId]={BUNDLE_ID}")
    app_id = apps["data"][0]["id"]
    _, groups = api("GET", f"/v1/apps/{app_id}/subscriptionGroups?limit=50")
    subs = {}
    for g in groups.get("data", []):
        _, ss = api("GET", f"/v1/subscriptionGroups/{g['id']}/subscriptions?limit=50")
        for s in ss.get("data", []):
            subs[s["attributes"]["productId"]] = s
    failed = False
    for pid in PRODUCT_IDS:
        s = subs.get(pid)
        if not s:
            print("MISSING subscription", pid); failed = True; continue
        state = s["attributes"].get("state")
        print("SUB", pid, s["id"], state)
        if state in DONE:
            continue
        if state != "READY_TO_SUBMIT":
            print(f"NOT READY {pid}: {state}"); failed = True; continue
        code, resp = api("POST", "/v1/subscriptionSubmissions", {"data": {
            "type": "subscriptionSubmissions",
            "relationships": {"subscription": {"data": {"type": "subscriptions", "id": s["id"]}}}}})
        print("POST subscriptionSubmissions", pid, "->", code, resp.get("data", {}).get("id") if code < 300 else resp)
        if code >= 300:
            failed = True
    time.sleep(3)
    for pid in PRODUCT_IDS:
        if pid in subs:
            _, s = api("GET", f"/v1/subscriptions/{subs[pid]['id']}")
            print("AFTER", pid, s["data"]["attributes"].get("state"))
    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
