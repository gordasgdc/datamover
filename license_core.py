"""
license_core.py — logica centrala de codare/semnare/verificare a
codurilor seriale, folosita atat de unealta de generare (keygen.py,
generate_serial.py — raman la tine, NU se distribuie cu aplicatia) cat
si de validatorul care se distribuie cu aplicatia (license_validator.py).

Cum functioneaza, pe scurt
---------------------------
1. Generezi O SINGURA DATA o pereche de chei Ed25519 (keygen.py).
   Cheia PRIVATA ramane la tine, secreta — NU intra niciodata in
   aplicatia distribuita. Cheia PUBLICA se lipeste direct in codul
   aplicatiei (license_validator.py) — e sigur sa fie publica, asta e
   ideea din spatele criptografiei asimetrice.

2. Pentru fiecare client, generezi un cod serial (generate_serial.py) —
   un pachet de date (nume/email client, data expirarii optionala) SEMNAT
   cu cheia privata. Doar tu poti genera semnaturi valide.

3. Aplicatia distribuita (folosind doar cheia PUBLICA) verifica daca
   semnatura codului introdus de utilizator e intr-adevar una generata
   de cheia ta privata. Fara conexiune la internet, fara server propriu.

De ce Ed25519 si nu o "formula" facuta de mana: un cod bazat pe o
formula proprie poate fi spart prin inginerie inversa a aplicatiei
insesi. Cu semnatura criptografica asimetrica, chiar daca cineva vede
tot codul sursa (inclusiv cheia PUBLICA), tot nu poate genera coduri
noi valide — ar avea nevoie de cheia PRIVATA, pe care n-o distribui
niciodata.
"""

from __future__ import annotations
import base64
import hashlib
import json
import time
from dataclasses import dataclass

from cryptography.hazmat.primitives.asymmetric import ed25519
from cryptography.exceptions import InvalidSignature


@dataclass
class LicensePayload:
    product_id: str
    customer: str = ""       # optional - poate fi gol, ca sa scurtezi codul
    expires_at: int = 0


def _product_short_code(product_id):
    """Cod scurt, fara coliziuni, pentru un product_id — spre deosebire
    de o simpla trunchiere la primele N caractere (care ar face
    'gdc-produs-a' si 'gdc-produs-b' sa para identice daca ambele incep
    la fel), un hash scurt distinge corect orice doua product_id-uri
    diferite, oricat de asemanatoare ar fi ca text."""
    import hashlib
    digest = hashlib.sha256(product_id.encode("utf-8")).digest()
    return base64.b32encode(digest[:5]).decode("ascii").rstrip("=")  # 8 caractere, fara coliziuni practice


def _payload_to_bytes(payload):
    data = {"p": _product_short_code(payload.product_id), "e": payload.expires_at}
    if payload.customer:
        data["c"] = payload.customer
    return json.dumps(data, separators=(",", ":"), sort_keys=True).encode("utf-8")


def _bytes_to_payload(data, resolved_product_id=""):
    obj = json.loads(data.decode("utf-8"))
    return LicensePayload(product_id=resolved_product_id or obj["p"], customer=obj.get("c", ""), expires_at=obj["e"])


def generate_keypair():
    """Genereaza o pereche noua de chei. Intoarce (private_key_b64, public_key_b64).
    Apelata O SINGURA DATA, niciodata din interiorul aplicatiei distribuite."""
    private_key = ed25519.Ed25519PrivateKey.generate()
    public_key = private_key.public_key()
    private_bytes = private_key.private_bytes_raw()
    public_bytes = public_key.public_bytes_raw()
    return (
        base64.b64encode(private_bytes).decode("ascii"),
        base64.b64encode(public_bytes).decode("ascii"),
    )


def _format_serial(raw):
    b32 = base64.b32encode(raw).decode("ascii").rstrip("=")
    groups = [b32[i:i + 4] for i in range(0, len(b32), 4)]
    return "-".join(groups)


def _parse_serial(serial):
    cleaned = serial.replace("-", "").replace(" ", "").upper()
    padding = "=" * ((8 - len(cleaned) % 8) % 8)
    return base64.b32decode(cleaned + padding)


def generate_serial(private_key_b64, payload):
    """Genereaza un cod serial nou, semnat cu cheia privata. Foloseste
    asta doar tu, local — niciodata din aplicatia distribuita clientilor."""
    private_bytes = base64.b64decode(private_key_b64)
    private_key = ed25519.Ed25519PrivateKey.from_private_bytes(private_bytes)

    payload_bytes = _payload_to_bytes(payload)
    signature = private_key.sign(payload_bytes)

    packed = len(payload_bytes).to_bytes(2, "big") + payload_bytes + signature
    return _format_serial(packed)


@dataclass
class ValidationResult:
    valid: bool
    payload: object = None
    error: str = None
    expired: bool = False


def generate_serial_compact(private_key_b64, product_id, expires_at=0, machine_id_b32=None):
    """Genereaza un cod serial folosind un format de payload FIX, binar
    (4 octeti hash produs + 8 octeti timestamp expirare + 4 octeti
    identificator aleator unic + 6 octeti hash masina = 22 octeti),
    fara JSON.

    machine_id_b32: string-ul Base32 pe care clientul il vede si il
    trimite (afisat de get_machine_id_display() din pluginul C++). Daca
    None, codul NU e legat de nicio masina anume (functioneaza oriunde
    — comportamentul vechi)."""
    import struct, os
    private_bytes = base64.b64decode(private_key_b64)
    private_key = ed25519.Ed25519PrivateKey.from_private_bytes(private_bytes)

    product_hash = hashlib.sha512(product_id.encode("utf-8")).digest()[:4]
    nonce = os.urandom(4)

    if machine_id_b32:
        machine_hash = _base32_decode_str(machine_id_b32)
        if len(machine_hash) != 6:
            raise ValueError(f"machine_id_b32 invalid — asteptat 6 octeti dupa decodare, "
                              f"am primit {len(machine_hash)}. Verifica ca ai copiat corect "
                              f"ID-ul afisat de client.")
    else:
        machine_hash = b"\x00" * 6

    payload_bytes = product_hash + struct.pack(">Q", expires_at) + nonce + machine_hash
    signature = private_key.sign(payload_bytes)
    packed = payload_bytes + signature
    return _format_serial(packed)


def _base32_decode_str(s):
    """Decodeaza un string Base32 (posibil fara padding '=', asa cum il
    afiseaza get_machine_id_display() in C++) inapoi in octeti bruti."""
    cleaned = s.strip().replace("-", "").replace(" ", "").upper()
    padding = "=" * ((8 - len(cleaned) % 8) % 8)
    return base64.b32decode(cleaned + padding)


def validate_serial_compact(public_key_b64, serial, product_id, machine_id_b32=None):
    """Verifica un cod generat cu generate_serial_compact(). Daca
    machine_id_b32 e dat, verifica si potrivirea cu masina — util pentru
    testare din Python a comportamentului identic cu C++."""
    import struct
    try:
        public_bytes = base64.b64decode(public_key_b64)
        public_key = ed25519.Ed25519PublicKey.from_public_bytes(public_bytes)

        packed = _parse_serial(serial)
        if len(packed) != 22 + 64:
            return ValidationResult(valid=False, error="Format de cod serial invalid (lungime gresita).")

        payload_bytes = packed[:22]
        signature = packed[22:]

        public_key.verify(signature, payload_bytes)

        stored_hash = payload_bytes[:4]
        expected_hash = hashlib.sha512(product_id.encode("utf-8")).digest()[:4]
        if stored_hash != expected_hash:
            return ValidationResult(valid=False, error="Acest cod e pentru alt produs.")

        (expires_at,) = struct.unpack(">Q", payload_bytes[4:12])

        stored_machine_hash = payload_bytes[16:22]
        if stored_machine_hash != b"\x00" * 6:
            current_machine_hash = _base32_decode_str(machine_id_b32) if machine_id_b32 else None
            if current_machine_hash != stored_machine_hash:
                return ValidationResult(valid=False, error="Acest cod e activat pentru alt calculator.")

    except InvalidSignature:
        return ValidationResult(valid=False, error="Cod serial invalid — semnatura nu se potriveste.")
    except Exception as e:
        return ValidationResult(valid=False, error=f"Cod serial invalid sau corupt ({e}).")

    if expires_at and expires_at < int(time.time()):
        return ValidationResult(valid=False, expired=True, error="Codul serial a expirat.")

    return ValidationResult(valid=True, payload=LicensePayload(product_id=product_id, expires_at=expires_at))


def validate_serial(public_key_b64, serial, expected_product_id=None):
    """Verifica un cod serial folosind DOAR cheia publica. Aceasta e
    functia pe care o foloseste aplicatia distribuita."""
    try:
        public_bytes = base64.b64decode(public_key_b64)
        public_key = ed25519.Ed25519PublicKey.from_public_bytes(public_bytes)

        packed = _parse_serial(serial)
        payload_len = int.from_bytes(packed[0:2], "big")
        payload_bytes = packed[2:2 + payload_len]
        signature = packed[2 + payload_len:]

        if len(signature) != 64:
            return ValidationResult(valid=False, error="Format de cod serial invalid.")

        public_key.verify(signature, payload_bytes)

        expected_short_code = _product_short_code(expected_product_id) if expected_product_id else ""
        obj = json.loads(payload_bytes.decode("utf-8"))
        stored_short_code = obj["p"]
        product_matches = (stored_short_code == expected_short_code) if expected_product_id else True
        payload = _bytes_to_payload(payload_bytes, resolved_product_id=expected_product_id if product_matches else stored_short_code)

    except InvalidSignature:
        return ValidationResult(valid=False, error="Cod serial invalid — semnatura nu se potriveste.")
    except Exception as e:
        return ValidationResult(valid=False, error=f"Cod serial invalid sau corupt ({e}).")

    if expected_product_id and not product_matches:
        return ValidationResult(valid=False, error="Acest cod e pentru alt produs.")

    if payload.expires_at and payload.expires_at < int(time.time()):
        return ValidationResult(valid=False, payload=payload, expired=True, error="Codul serial a expirat.")

    return ValidationResult(valid=True, payload=payload)
