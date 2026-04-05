"""
Servicio Hedera para KPEG.
Integra File Service, Consensus Service (HCS) y Token Service (HTS/NFT).
Usa el SDK de Python hiero-sdk-python.
"""
import json
import os
import sys

from dotenv import load_dotenv

# Cargar .env desde la raíz del proyecto
load_dotenv(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '.env'))

from hiero_sdk_python import (
    AccountId,
    Client,
    Network,
    PrivateKey,
    ResponseCode,
    TokenCreateTransaction,
    TokenId,
    TokenMintTransaction,
    TokenType,
    TopicCreateTransaction,
    TopicId,
    TopicMessageSubmitTransaction,
)
from hiero_sdk_python.file.file_create_transaction import FileCreateTransaction

# ══════════════════════════════════════
# ESTADO PERSISTENTE (topic ID + NFT collection ID)
# ══════════════════════════════════════

STATE_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), '.hedera_state.json')


def _load_state():
    if os.path.exists(STATE_FILE):
        with open(STATE_FILE, 'r') as f:
            return json.load(f)
    return {}


def _save_state(state):
    with open(STATE_FILE, 'w') as f:
        json.dump(state, f, indent=2)


# ══════════════════════════════════════
# CLIENTE HEDERA
# ══════════════════════════════════════

_client = None
_operator_key = None


def _get_client():
    """Inicializar cliente Hedera (singleton)."""
    global _client, _operator_key
    if _client is not None:
        return _client, _operator_key

    network_name = os.getenv('NETWORK', os.getenv('HEDERA_NETWORK', 'testnet'))
    operator_id_str = os.getenv('OPERATOR_ID', os.getenv('HEDERA_ACCOUNT_ID', ''))
    operator_key_str = os.getenv('OPERATOR_KEY', os.getenv('HEDERA_PRIVATE_KEY', ''))

    if not operator_id_str or not operator_key_str:
        print('⚠️  Hedera: faltan credenciales (OPERATOR_ID / OPERATOR_KEY)')
        return None, None

    try:
        network = Network(network_name)
        _client = Client(network)
        operator_id = AccountId.from_string(operator_id_str)
        _operator_key = PrivateKey.from_string_ecdsa(operator_key_str)
        _client.set_operator(operator_id, _operator_key)
        print(f'🔗 Hedera client: {network_name} / {operator_id_str}')
        return _client, _operator_key
    except Exception as e:
        print(f'⚠️  Hedera client init error: {e}')
        _client = None
        _operator_key = None
        return None, None


def is_available():
    """Comprobar si el servicio Hedera está configurado."""
    client, key = _get_client()
    return client is not None


# ══════════════════════════════════════
# SETUP — crear topic HCS + colección NFT (una sola vez)
# ══════════════════════════════════════

def setup():
    """Crear topic HCS y colección NFT si no existen. Devuelve el estado."""
    client, operator_key = _get_client()
    if client is None:
        return {'error': 'Hedera client not available'}

    state = _load_state()
    operator_id = client.operator_account_id

    # Crear topic HCS
    if not state.get('topic_id'):
        try:
            print('  Creating HCS topic...')
            receipt = (
                TopicCreateTransaction(
                    memo='KPEG Image Registry',
                    admin_key=operator_key.public_key(),
                )
                .freeze_with(client)
                .sign(operator_key)
                .execute(client)
            )
            if receipt.status == ResponseCode.SUCCESS and receipt.topic_id:
                state['topic_id'] = str(receipt.topic_id)
                print(f'  ✅ Topic created: {state["topic_id"]}')
            else:
                return {'error': f'Topic creation failed: {ResponseCode(receipt.status).name}'}
        except Exception as e:
            return {'error': f'Topic creation error: {e}'}

    # Crear colección NFT
    if not state.get('nft_token_id'):
        try:
            print('  Creating NFT collection...')
            tx = (
                TokenCreateTransaction()
                .set_token_name('KPEG Photo')
                .set_token_symbol('KPEG')
                .set_token_type(TokenType.NON_FUNGIBLE_UNIQUE)
                .set_treasury_account_id(operator_id)
                .set_initial_supply(0)
                .set_admin_key(operator_key)
                .set_supply_key(operator_key)
                .freeze_with(client)
            )
            tx.sign(operator_key)
            receipt = tx.execute(client)
            if receipt.token_id:
                state['nft_token_id'] = str(receipt.token_id)
                print(f'  ✅ NFT collection created: {state["nft_token_id"]}')
            else:
                return {'error': 'NFT creation failed: no token_id in receipt'}
        except Exception as e:
            return {'error': f'NFT creation error: {e}'}

    _save_state(state)
    return {
        'status': 'ok',
        'topic_id': state.get('topic_id'),
        'nft_token_id': state.get('nft_token_id'),
    }


# ══════════════════════════════════════
# FILE SERVICE — subir .kpeg
# ══════════════════════════════════════

def create_file(content_bytes):
    """Crear archivo en Hedera File Service. Devuelve file_id o None."""
    client, operator_key = _get_client()
    if client is None:
        return None

    try:
        file_key = PrivateKey.generate_ed25519()
        receipt = (
            FileCreateTransaction()
            .set_keys(file_key.public_key())
            .set_contents(content_bytes)
            .set_file_memo('KPEG ultra-compressed image')
            .freeze_with(client)
            .sign(file_key)
            .execute(client)
        )
        if receipt.status == ResponseCode.SUCCESS and receipt.file_id:
            file_id = str(receipt.file_id)
            print(f'  📁 File created: {file_id} ({len(content_bytes)} bytes)')
            return file_id
        else:
            print(f'  ⚠️  File creation failed: {ResponseCode(receipt.status).name}')
            return None
    except Exception as e:
        print(f'  ⚠️  File creation error: {e}')
        return None


# ══════════════════════════════════════
# CONSENSUS SERVICE (HCS) — log de quién subió qué imagen
# ══════════════════════════════════════

def log_message(message_dict):
    """Enviar mensaje a HCS topic. Devuelve (topic_id, sequence_number) o (None, None)."""
    client, operator_key = _get_client()
    if client is None:
        return None, None

    state = _load_state()
    topic_id = state.get('topic_id')
    if not topic_id:
        print('  ⚠️  HCS topic not initialized')
        return None, None

    try:
        message_str = json.dumps(message_dict, separators=(',', ':'))
        receipt = (
            TopicMessageSubmitTransaction(topic_id=TopicId.from_string(topic_id), message=message_str)
            .freeze_with(client)
            .sign(operator_key)
            .execute(client)
        )
        if receipt.status == ResponseCode.SUCCESS:
            # El receipt del topic message no siempre tiene sequence_number en el Python SDK
            # Usamos el transaction_id como referencia
            tx_id = str(receipt.transaction_id) if receipt.transaction_id else None
            print(f'  📝 HCS logged on topic {topic_id} (tx: {tx_id})')
            return topic_id, tx_id
        else:
            print(f'  ⚠️  HCS log failed: {ResponseCode(receipt.status).name}')
            return None, None
    except Exception as e:
        print(f'  ⚠️  HCS log error: {e}')
        return None, None


# ══════════════════════════════════════
# TOKEN SERVICE (HTS) — mintear NFT por cada imagen
# ══════════════════════════════════════

def mint_nft(metadata_str):
    """Mintear un NFT para una imagen. Devuelve (nft_token_id, serial_or_tx) o (None, None)."""
    client, operator_key = _get_client()
    if client is None:
        return None, None

    state = _load_state()
    nft_token_id = state.get('nft_token_id')
    if not nft_token_id:
        print('  ⚠️  NFT collection not initialized')
        return None, None

    try:
        receipt = (
            TokenMintTransaction()
            .set_token_id(TokenId.from_string(nft_token_id))
            .set_metadata([metadata_str.encode('utf-8') if isinstance(metadata_str, str) else metadata_str])
            .freeze_with(client)
            .sign(operator_key)
            .execute(client)
        )
        if receipt.status == ResponseCode.SUCCESS:
            tx_id = str(receipt.transaction_id) if receipt.transaction_id else None
            # Incrementar contador local como referencia del serial
            serial_count = state.get('nft_serial_count', 0) + 1
            state['nft_serial_count'] = serial_count
            _save_state(state)
            print(f'  🎨 NFT minted: {nft_token_id} #{serial_count} (tx: {tx_id})')
            return nft_token_id, str(serial_count)
        else:
            print(f'  ⚠️  NFT mint failed: {ResponseCode(receipt.status).name}')
            return None, None
    except Exception as e:
        print(f'  ⚠️  NFT mint error: {e}')
        return None, None


# ══════════════════════════════════════
# REGISTRO COMPLETO — las 3 operaciones para una imagen
# ══════════════════════════════════════

def register_image(kpeg_bytes, image_id, user_id='operator'):
    """
    Registrar imagen en Hedera (3 servicios):
    1. File Service — subir .kpeg
    2. HCS — log de quién subió qué
    3. HTS — mintear NFT

    Devuelve dict con la info de Hedera (best-effort, campos pueden ser None).
    """
    import time
    timestamp = int(time.time())

    # 1. Subir archivo
    file_id = create_file(kpeg_bytes)

    # 2. Log en HCS
    topic_id, topic_tx_id = log_message({
        'action': 'upload',
        'user': user_id,
        'image_id': image_id,
        'file_id': file_id,
        'timestamp': timestamp,
        'size_bytes': len(kpeg_bytes),
    })

    # 3. Mintear NFT con referencia al file_id
    nft_metadata = f'kpeg:{image_id}|file:{file_id or "pending"}'
    nft_token_id, nft_serial = mint_nft(nft_metadata)

    state = _load_state()
    network = os.getenv('NETWORK', os.getenv('HEDERA_NETWORK', 'testnet'))

    return {
        'file_id': file_id,
        'topic_id': topic_id or state.get('topic_id'),
        'topic_tx_id': topic_tx_id,
        'nft_token_id': nft_token_id or state.get('nft_token_id'),
        'nft_serial': nft_serial,
        'network': network,
    }


def get_state():
    """Devolver estado actual de Hedera (topic_id, nft_token_id, etc)."""
    state = _load_state()
    network = os.getenv('NETWORK', os.getenv('HEDERA_NETWORK', 'testnet'))
    return {
        'available': is_available(),
        'network': network,
        'account_id': os.getenv('OPERATOR_ID', os.getenv('HEDERA_ACCOUNT_ID', '')),
        'topic_id': state.get('topic_id'),
        'nft_token_id': state.get('nft_token_id'),
        'nft_serial_count': state.get('nft_serial_count', 0),
    }
