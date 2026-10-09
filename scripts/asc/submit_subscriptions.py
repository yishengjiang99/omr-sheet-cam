#!/usr/bin/env python3
"""Put the Music Reader Pro subscriptions into the same review submission as the app version.

Apple: the first auto-renewable subscription (and its new group) must be submitted together with an
app version (POST /v1/subscriptionSubmissions answers FIRST_SUBSCRIPTION_MUST_BE_SUBMITTED_ON_VERSION).
API 4.4.1 workflow: one draft reviewSubmission (READY_FOR_REVIEW) holding reviewSubmissionItems for
  - the appStoreVersion (VERSION_STRING),
  - the subscription group version (PREPARE_FOR_SUBMISSION),
  - each subscription version (PREPARE_FOR_SUBMISSION).
This script builds that draft but does NOT mark it submitted: the next step of
asc-submit-app-store.yml reuses the READY_FOR_REVIEW submission that already has items and submits it.
Subscriptions already WAITING_FOR_REVIEW / IN_REVIEW / APPROVED are skipped.
Exits 1 if a subscription is not READY_TO_SUBMIT or an item cannot be added.
Env: APP_STORE_CONNECT_KEY_ID, APP_STORE_CONNECT_ISSUER_ID, APP_STORE_CONNECT_API_KEY_P8,
     BUNDLE_ID, VERSION_STRING
"""
from __future__ import annotations
import json, os, sys, time
import jwt, requests

BASE = "https://api.appstoreconnect.apple.com"
BUNDLE_ID = os.environ.get("BUNDLE_ID", "com.ragnus.vp").strip()
VERSION_STRING = os.environ.get("VERSION_STRING", "1.0").strip()
PRODUCT_IDS = ["com.ragnus.vp.pro.yearly", "com.ragnus.vp.pro.monthly"]
GROUP_REF = "Music Reader Pro"
DONE = {"WAITING_FOR_REVIEW", "IN_REVIEW", "APPROVED"}
EDITABLE = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY", "READY_FOR_REVIEW"}


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


def must(method, path, body=None):
    code, j = api(method, path, body)
    if code >= 300:
        raise SystemExit(f"{method} {path} -> {code}: {json.dumps(j)[:1500]}")
    return j


def add_item(sub_id, rel_name, rel_type, rel_id):
    code, j = api("POST", "/v1/reviewSubmissionItems", {"data": {
        "type": "reviewSubmissionItems",
        "relationships": {"reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sub_id}},
                          rel_name: {"data": {"type": rel_type, "id": rel_id}}}}})
    blob = json.dumps(j)
    ok = code < 300 or "ALREADY" in blob.upper() or "DUPLICATE" in blob.upper()
    print(f"ADD ITEM {rel_name} {rel_id} -> {code}", (j.get("data") or {}).get("id") if code < 300 else blob[:1500])
    return ok


def draft_version(versions):
    for v in sorted(versions, key=lambda v: -(v["attributes"].get("version") or 0)):
        if v["attributes"].get("state") in ("PREPARE_FOR_SUBMISSION", "READY_FOR_REVIEW"):
            return v
    return None


def main():
    app_id = must("GET", f"/v1/apps?filter[bundleId]={BUNDLE_ID}")["data"][0]["id"]
    ver = must("GET", f"/v1/apps/{app_id}/appStoreVersions?filter[platform]=IOS&filter[versionString]={VERSION_STRING}")["data"][0]
    vstate = ver["attributes"].get("appStoreState")
    print("VERSION", ver["id"], VERSION_STRING, vstate)
    if vstate not in EDITABLE:
        raise SystemExit(f"version {VERSION_STRING} is {vstate}, not editable; pull it from review first")

    groups = must("GET", f"/v1/apps/{app_id}/subscriptionGroups?limit=50")["data"]
    group = next(g for g in groups if g["attributes"]["referenceName"] == GROUP_REF)
    subs = {s["attributes"]["productId"]: s for s in must("GET", f"/v1/subscriptionGroups/{group['id']}/subscriptions?limit=50")["data"]}

    todo = []
    for pid in PRODUCT_IDS:
        s = subs.get(pid)
        if not s:
            raise SystemExit(f"MISSING subscription {pid}")
        state = s["attributes"].get("state")
        print("SUB", pid, s["id"], state)
        if state in DONE:
            continue
        if state != "READY_TO_SUBMIT":
            raise SystemExit(f"NOT READY {pid}: {state}")
        sv = draft_version(must("GET", f"/v1/subscriptions/{s['id']}/versions?limit=50")["data"])
        if not sv:
            raise SystemExit(f"no draft subscriptionVersion for {pid}")
        print("  subscriptionVersion", sv["id"], sv["attributes"])
        todo.append((pid, sv))
    if not todo:
        print("RESULT subscriptions already submitted/approved; nothing to add")
        return

    gv = draft_version(must("GET", f"/v1/subscriptionGroups/{group['id']}/versions?limit=50")["data"])
    print("GROUP", group["id"], "version", gv and (gv["id"], gv["attributes"]))

    # Reuse an open draft submission, else create one.
    rss = must("GET", f"/v1/apps/{app_id}/reviewSubmissions?filter[platform]=IOS&limit=50")["data"]
    draft = next((r for r in rss if r["attributes"].get("state") == "READY_FOR_REVIEW"), None)
    if draft:
        print("REUSE reviewSubmission", draft["id"])
    else:
        draft = must("POST", "/v1/reviewSubmissions", {"data": {"type": "reviewSubmissions", "attributes": {"platform": "IOS"},
                     "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})["data"]
        print("CREATED reviewSubmission", draft["id"], draft["attributes"])
    rs_id = draft["id"]

    ok = add_item(rs_id, "appStoreVersion", "appStoreVersions", ver["id"])
    if gv:
        ok = add_item(rs_id, "subscriptionGroupVersion", "subscriptionGroupVersions", gv["id"]) and ok
    for pid, sv in todo:
        ok = add_item(rs_id, "subscriptionVersion", "subscriptionVersions", sv["id"]) and ok

    items = must("GET", f"/v1/reviewSubmissions/{rs_id}/items?limit=50")["data"]
    for it in items:
        print("ITEM", it["id"], it["attributes"].get("state"),
              {k: (v.get("data") or {}).get("id") for k, v in (it.get("relationships") or {}).items() if isinstance(v, dict) and v.get("data")})
    print("DRAFT_REVIEW_SUBMISSION", rs_id, "items=", len(items))
    if not ok:
        raise SystemExit("could not add every item to the draft review submission (see ADD ITEM lines); version NOT submitted")


if __name__ == "__main__":
    main()
