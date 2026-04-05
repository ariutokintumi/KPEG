-- ══════════════════════════════════════════════════════
-- KPEG Library Database Dump
-- Generated for debugging encoder/library integration
-- NOTE: file_path columns reference files on disk at API/library/
--       Photos are NOT embedded in the DB, only paths are stored.
-- ══════════════════════════════════════════════════════

-- ── SCHEMA ──

CREATE TABLE hedera_metadata (
            image_id TEXT PRIMARY KEY,
            file_id TEXT,
            topic_id TEXT,
            topic_tx_id TEXT,
            nft_token_id TEXT,
            nft_serial TEXT,
            network TEXT,
            created_at TEXT NOT NULL
        );

CREATE TABLE object_photos (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            object_id TEXT NOT NULL,
            file_path TEXT NOT NULL,
            FOREIGN KEY (object_id) REFERENCES objects(object_id) ON DELETE CASCADE
        );

CREATE TABLE objects (
            object_id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            category TEXT NOT NULL DEFAULT 'other',
            photo_count INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL
        );

CREATE TABLE people (
            user_id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            selfie_count INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL
        );

CREATE TABLE people_selfies (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id TEXT NOT NULL,
            file_path TEXT NOT NULL,
            timestamp INTEGER NOT NULL,
            FOREIGN KEY (user_id) REFERENCES people(user_id) ON DELETE CASCADE
        );

CREATE TABLE place_photos (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            place_id TEXT NOT NULL,
            file_path TEXT NOT NULL,
            lat REAL,
            lng REAL,
            compass_heading REAL,
            camera_tilt REAL,
            timestamp INTEGER NOT NULL,
            FOREIGN KEY (place_id) REFERENCES places(place_id) ON DELETE CASCADE
        );

CREATE TABLE places (
            place_id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            photo_count INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL
        );

-- ── PEOPLE (2 rows) ──
-- Columns: user_id, name, selfie_count, created_at
INSERT INTO people (user_id, name, selfie_count, created_at) VALUES ('usr_josemaria_40346', 'JoseMaria', 3, '2026-04-04T23:10:40.386872');
INSERT INTO people (user_id, name, selfie_count, created_at) VALUES ('usr_german_48869', 'German', 2, '2026-04-05T00:52:29.151689');

-- ── PEOPLE_SELFIES (5 rows) ──
-- Columns: id, user_id, file_path, timestamp
INSERT INTO people_selfies (id, user_id, file_path, timestamp) VALUES (1, 'usr_josemaria_40346', '/home/jmaria/PROYECTOS/KPEG/API/library/people/usr_josemaria_40346/selfie_0.jpg', 1775337040);
INSERT INTO people_selfies (id, user_id, file_path, timestamp) VALUES (2, 'usr_josemaria_40346', '/home/jmaria/PROYECTOS/KPEG/API/library/people/usr_josemaria_40346/selfie_1.jpg', 1775337041);
INSERT INTO people_selfies (id, user_id, file_path, timestamp) VALUES (6, 'usr_josemaria_40346', '/home/jmaria/PROYECTOS/KPEG/API/library/people/usr_josemaria_40346/selfie_2.jpg', 1775341807);
INSERT INTO people_selfies (id, user_id, file_path, timestamp) VALUES (7, 'usr_german_48869', '/home/jmaria/PROYECTOS/KPEG/API/library/people/usr_german_48869/selfie_0.jpg', 1775343148);
INSERT INTO people_selfies (id, user_id, file_path, timestamp) VALUES (8, 'usr_german_48869', '/home/jmaria/PROYECTOS/KPEG/API/library/people/usr_german_48869/selfie_1.jpg', 1775343149);

-- ── PLACES (1 rows) ──
-- Columns: place_id, name, photo_count, created_at
INSERT INTO places (place_id, name, photo_count, created_at) VALUES ('place_hall_ethglobal_52568', 'Hall ETHGlobal', 7, '2026-04-04T23:12:32.804111');

-- ── PLACE_PHOTOS (7 rows) ──
-- Columns: id, place_id, file_path, lat, lng, compass_heading, camera_tilt, timestamp
INSERT INTO place_photos (id, place_id, file_path, lat, lng, compass_heading, camera_tilt, timestamp) VALUES (1, 'place_hall_ethglobal_52568', '/home/jmaria/PROYECTOS/KPEG/API/library/places/place_hall_ethglobal_52568/photo_0.jpg', 43.5497417, 7.0179222, -92.17991884979027, 51.57637102914218, 1775337099);
INSERT INTO place_photos (id, place_id, file_path, lat, lng, compass_heading, camera_tilt, timestamp) VALUES (2, 'place_hall_ethglobal_52568', '/home/jmaria/PROYECTOS/KPEG/API/library/places/place_hall_ethglobal_52568/photo_1.jpg', 43.5497417, 7.0179222, -159.12305369757047, 68.88294219292789, 1775337108);
INSERT INTO place_photos (id, place_id, file_path, lat, lng, compass_heading, camera_tilt, timestamp) VALUES (3, 'place_hall_ethglobal_52568', '/home/jmaria/PROYECTOS/KPEG/API/library/places/place_hall_ethglobal_52568/photo_2.jpg', 43.5497417, 7.0179222, -70.22388644200159, 60.77477080154789, 1775337118);
INSERT INTO place_photos (id, place_id, file_path, lat, lng, compass_heading, camera_tilt, timestamp) VALUES (4, 'place_hall_ethglobal_52568', '/home/jmaria/PROYECTOS/KPEG/API/library/places/place_hall_ethglobal_52568/photo_3.jpg', 43.5497417, 7.0179222, 19.969825349980017, 70.48171942661695, 1775337129);
INSERT INTO place_photos (id, place_id, file_path, lat, lng, compass_heading, camera_tilt, timestamp) VALUES (5, 'place_hall_ethglobal_52568', '/home/jmaria/PROYECTOS/KPEG/API/library/places/place_hall_ethglobal_52568/photo_4.jpg', 43.5497417, 7.0179222, -30.59641978334074, 43.30436271338757, 1775337150);
INSERT INTO place_photos (id, place_id, file_path, lat, lng, compass_heading, camera_tilt, timestamp) VALUES (6, 'place_hall_ethglobal_52568', '/home/jmaria/PROYECTOS/KPEG/API/library/places/place_hall_ethglobal_52568/photo_5.jpg', NULL, NULL, NULL, NULL, 0);
INSERT INTO place_photos (id, place_id, file_path, lat, lng, compass_heading, camera_tilt, timestamp) VALUES (7, 'place_hall_ethglobal_52568', '/home/jmaria/PROYECTOS/KPEG/API/library/places/place_hall_ethglobal_52568/photo_6.jpg', NULL, NULL, NULL, NULL, 0);

-- ── OBJECTS (28 rows) ──
-- Columns: object_id, name, category, photo_count, created_at
INSERT INTO objects (object_id, name, category, photo_count, created_at) VALUES ('obj_palmera_92652', 'palmera', 'decoration', 1, '2026-04-04T23:13:13.324340');
INSERT INTO objects (object_id, name, category, photo_count, created_at) VALUES ('obj_amaca_14625', 'amaca', 'furniture', 1, '2026-04-04T23:13:34.403900');
INSERT INTO objects (object_id, name, category, photo_count, created_at) VALUES ('obj_silla_34421', 'silla', 'furniture', 1, '2026-04-04T23:13:54.288226');
INSERT INTO objects (object_id, name, category, photo_count, created_at) VALUES ('obj_agua_67313', 'agua', 'other', 1, '2026-04-05T00:16:08.406541');
INSERT INTO objects (object_id, name, category, photo_count, created_at) VALUES ('obj_banner_13155', 'banner', 'decoration', 1, '2026-04-05T00:28:33.423694');
INSERT INTO objects (object_id, name, category, photo_count, created_at) VALUES ('obj_extintor_64578', 'extintor', 'other', 1, '2026-04-05T00:29:24.884850');
INSERT INTO objects (object_id, name, category, photo_count, created_at) VALUES ('obj_techo_53480', 'techo', 'decoration', 1, '2026-04-05T00:30:53.703923');
INSERT INTO objects (object_id, name, category, photo_count, created_at) VALUES ('obj_columna_5151', 'columna', 'decoration', 1, '2026-04-05T00:31:45.381487');
INSERT INTO objects (object_id, name, category, photo_count, created_at) VALUES ('obj_rollup_28208', 'rollup', 'decoration', 1, '2026-04-05T00:55:28.522736');
INSERT INTO objects (object_id, name, category, photo_count, created_at) VALUES ('obj_sombrilla_52180', 'sombrilla', 'decoration', 1, '2026-04-05T00:55:52.456876');
INSERT INTO objects (object_id, name, category, photo_count, created_at) VALUES ('obj_cojines_69909', 'cojines', 'decoration', 1, '2026-04-05T00:56:10.206396');
INSERT INTO objects (object_id, name, category, photo_count, created_at) VALUES ('obj_maceta_96703', 'maceta', 'decoration', 1, '2026-04-05T00:56:37.239433');
INSERT INTO objects (object_id, name, category, photo_count, created_at) VALUES ('obj_mesita_19161', 'mesita', 'decoration', 1, '2026-04-05T00:56:59.456432');
INSERT INTO objects (object_id, name, category, photo_count, created_at) VALUES ('obj_papelera_52259', 'papelera', 'decoration', 1, '2026-04-05T00:57:32.686096');
INSERT INTO objects (object_id, name, category, photo_count, created_at) VALUES ('obj_silla_2884', 'silla', 'furniture', 1, '2026-04-05T00:58:23.173811');
INSERT INTO objects (object_id, name, category, photo_count, created_at) VALUES ('obj_pasillo_22700', 'pasillo', 'decoration', 1, '2026-04-05T00:58:42.995726');
INSERT INTO objects (object_id, name, category, photo_count, created_at) VALUES ('obj_amaca_2_55162', 'amaca 2', 'furniture', 1, '2026-04-05T00:59:15.478516');
INSERT INTO objects (object_id, name, category, photo_count, created_at) VALUES ('obj_stand_85952', 'stand', 'decoration', 1, '2026-04-05T00:59:46.359064');
INSERT INTO objects (object_id, name, category, photo_count, created_at) VALUES ('obj_bar_9586', 'bar', 'other', 1, '2026-04-05T01:00:09.852243');
INSERT INTO objects (object_id, name, category, photo_count, created_at) VALUES ('obj_planta_30099', 'planta', 'decoration', 1, '2026-04-05T01:00:30.506005');
INSERT INTO objects (object_id, name, category, photo_count, created_at) VALUES ('obj_mesita_24092', 'mesita', 'furniture', 1, '2026-04-05T01:02:04.471498');
INSERT INTO objects (object_id, name, category, photo_count, created_at) VALUES ('obj_silla_74845', 'silla', 'furniture', 1, '2026-04-05T01:02:55.154729');
INSERT INTO objects (object_id, name, category, photo_count, created_at) VALUES ('obj_publi_868', 'publi', 'other', 1, '2026-04-05T01:03:21.231184');
INSERT INTO objects (object_id, name, category, photo_count, created_at) VALUES ('obj_foco_39855', 'foco', 'electronics', 1, '2026-04-05T01:04:00.502505');
INSERT INTO objects (object_id, name, category, photo_count, created_at) VALUES ('obj_mesa_38837', 'mesa', 'furniture', 1, '2026-04-05T01:05:39.126795');
INSERT INTO objects (object_id, name, category, photo_count, created_at) VALUES ('obj_laptop_67979', 'laptop', 'electronics', 1, '2026-04-05T01:06:08.224030');
INSERT INTO objects (object_id, name, category, photo_count, created_at) VALUES ('obj_cartel_techo_44058', 'cartel techo', 'decoration', 1, '2026-04-05T01:07:24.160455');
INSERT INTO objects (object_id, name, category, photo_count, created_at) VALUES ('obj_limpieza_26465', 'limpieza', 'furniture', 1, '2026-04-05T01:23:46.772273');

-- ── OBJECT_PHOTOS (28 rows) ──
-- Columns: id, object_id, file_path
INSERT INTO object_photos (id, object_id, file_path) VALUES (1, 'obj_palmera_92652', '/home/jmaria/PROYECTOS/KPEG/API/library/objects/obj_palmera_92652/photo_0.jpg');
INSERT INTO object_photos (id, object_id, file_path) VALUES (2, 'obj_amaca_14625', '/home/jmaria/PROYECTOS/KPEG/API/library/objects/obj_amaca_14625/photo_0.jpg');
INSERT INTO object_photos (id, object_id, file_path) VALUES (3, 'obj_silla_34421', '/home/jmaria/PROYECTOS/KPEG/API/library/objects/obj_silla_34421/photo_0.jpg');
INSERT INTO object_photos (id, object_id, file_path) VALUES (4, 'obj_agua_67313', '/home/jmaria/PROYECTOS/KPEG/API/library/objects/obj_agua_67313/photo_0.jpg');
INSERT INTO object_photos (id, object_id, file_path) VALUES (5, 'obj_banner_13155', '/home/jmaria/PROYECTOS/KPEG/API/library/objects/obj_banner_13155/photo_0.jpg');
INSERT INTO object_photos (id, object_id, file_path) VALUES (6, 'obj_extintor_64578', '/home/jmaria/PROYECTOS/KPEG/API/library/objects/obj_extintor_64578/photo_0.jpg');
INSERT INTO object_photos (id, object_id, file_path) VALUES (7, 'obj_techo_53480', '/home/jmaria/PROYECTOS/KPEG/API/library/objects/obj_techo_53480/photo_0.jpg');
INSERT INTO object_photos (id, object_id, file_path) VALUES (8, 'obj_columna_5151', '/home/jmaria/PROYECTOS/KPEG/API/library/objects/obj_columna_5151/photo_0.jpg');
INSERT INTO object_photos (id, object_id, file_path) VALUES (9, 'obj_rollup_28208', '/home/jmaria/PROYECTOS/KPEG/API/library/objects/obj_rollup_28208/photo_0.jpg');
INSERT INTO object_photos (id, object_id, file_path) VALUES (10, 'obj_sombrilla_52180', '/home/jmaria/PROYECTOS/KPEG/API/library/objects/obj_sombrilla_52180/photo_0.jpg');
INSERT INTO object_photos (id, object_id, file_path) VALUES (11, 'obj_cojines_69909', '/home/jmaria/PROYECTOS/KPEG/API/library/objects/obj_cojines_69909/photo_0.jpg');
INSERT INTO object_photos (id, object_id, file_path) VALUES (12, 'obj_maceta_96703', '/home/jmaria/PROYECTOS/KPEG/API/library/objects/obj_maceta_96703/photo_0.jpg');
INSERT INTO object_photos (id, object_id, file_path) VALUES (13, 'obj_mesita_19161', '/home/jmaria/PROYECTOS/KPEG/API/library/objects/obj_mesita_19161/photo_0.jpg');
INSERT INTO object_photos (id, object_id, file_path) VALUES (14, 'obj_papelera_52259', '/home/jmaria/PROYECTOS/KPEG/API/library/objects/obj_papelera_52259/photo_0.jpg');
INSERT INTO object_photos (id, object_id, file_path) VALUES (15, 'obj_silla_2884', '/home/jmaria/PROYECTOS/KPEG/API/library/objects/obj_silla_2884/photo_0.jpg');
INSERT INTO object_photos (id, object_id, file_path) VALUES (16, 'obj_pasillo_22700', '/home/jmaria/PROYECTOS/KPEG/API/library/objects/obj_pasillo_22700/photo_0.jpg');
INSERT INTO object_photos (id, object_id, file_path) VALUES (17, 'obj_amaca_2_55162', '/home/jmaria/PROYECTOS/KPEG/API/library/objects/obj_amaca_2_55162/photo_0.jpg');
INSERT INTO object_photos (id, object_id, file_path) VALUES (18, 'obj_stand_85952', '/home/jmaria/PROYECTOS/KPEG/API/library/objects/obj_stand_85952/photo_0.jpg');
INSERT INTO object_photos (id, object_id, file_path) VALUES (19, 'obj_bar_9586', '/home/jmaria/PROYECTOS/KPEG/API/library/objects/obj_bar_9586/photo_0.jpg');
INSERT INTO object_photos (id, object_id, file_path) VALUES (20, 'obj_planta_30099', '/home/jmaria/PROYECTOS/KPEG/API/library/objects/obj_planta_30099/photo_0.jpg');
INSERT INTO object_photos (id, object_id, file_path) VALUES (21, 'obj_mesita_24092', '/home/jmaria/PROYECTOS/KPEG/API/library/objects/obj_mesita_24092/photo_0.jpg');
INSERT INTO object_photos (id, object_id, file_path) VALUES (22, 'obj_silla_74845', '/home/jmaria/PROYECTOS/KPEG/API/library/objects/obj_silla_74845/photo_0.jpg');
INSERT INTO object_photos (id, object_id, file_path) VALUES (23, 'obj_publi_868', '/home/jmaria/PROYECTOS/KPEG/API/library/objects/obj_publi_868/photo_0.jpg');
INSERT INTO object_photos (id, object_id, file_path) VALUES (24, 'obj_foco_39855', '/home/jmaria/PROYECTOS/KPEG/API/library/objects/obj_foco_39855/photo_0.jpg');
INSERT INTO object_photos (id, object_id, file_path) VALUES (25, 'obj_mesa_38837', '/home/jmaria/PROYECTOS/KPEG/API/library/objects/obj_mesa_38837/photo_0.jpg');
INSERT INTO object_photos (id, object_id, file_path) VALUES (26, 'obj_laptop_67979', '/home/jmaria/PROYECTOS/KPEG/API/library/objects/obj_laptop_67979/photo_0.jpg');
INSERT INTO object_photos (id, object_id, file_path) VALUES (27, 'obj_cartel_techo_44058', '/home/jmaria/PROYECTOS/KPEG/API/library/objects/obj_cartel_techo_44058/photo_0.jpg');
INSERT INTO object_photos (id, object_id, file_path) VALUES (28, 'obj_limpieza_26465', '/home/jmaria/PROYECTOS/KPEG/API/library/objects/obj_limpieza_26465/photo_0.jpg');

-- ── HEDERA_METADATA (10 rows) ──
-- Columns: image_id, file_id, topic_id, topic_tx_id, nft_token_id, nft_serial, network, created_at
INSERT INTO hedera_metadata (image_id, file_id, topic_id, topic_tx_id, nft_token_id, nft_serial, network, created_at) VALUES ('d6038e99', '0.0.8511863', '0.0.8511578', NULL, '0.0.8511579', NULL, 'testnet', '2026-04-04T23:14:36.005465');
INSERT INTO hedera_metadata (image_id, file_id, topic_id, topic_tx_id, nft_token_id, nft_serial, network, created_at) VALUES ('5b7d95b8', '0.0.8512129', '0.0.8511578', '0.0.8511081@1775338572.636391401', '0.0.8511579', '1', 'testnet', '2026-04-04T23:36:23.041277');
INSERT INTO hedera_metadata (image_id, file_id, topic_id, topic_tx_id, nft_token_id, nft_serial, network, created_at) VALUES ('f72c917c', '0.0.8512158', '0.0.8511578', '0.0.8511081@1775338714.691797018', '0.0.8511579', '2', 'testnet', '2026-04-04T23:38:46.096665');
INSERT INTO hedera_metadata (image_id, file_id, topic_id, topic_tx_id, nft_token_id, nft_serial, network, created_at) VALUES ('1f111438', '0.0.8512762', '0.0.8511578', '0.0.8511081@1775341964.500331163', '0.0.8511579', '3', 'testnet', '2026-04-05T00:32:56.008901');
INSERT INTO hedera_metadata (image_id, file_id, topic_id, topic_tx_id, nft_token_id, nft_serial, network, created_at) VALUES ('7ce40aaa', '0.0.8512788', '0.0.8511578', '0.0.8511081@1775342172.121220588', '0.0.8511579', '4', 'testnet', '2026-04-05T00:36:21.624132');
INSERT INTO hedera_metadata (image_id, file_id, topic_id, topic_tx_id, nft_token_id, nft_serial, network, created_at) VALUES ('a9157ebf', '0.0.8513609', '0.0.8511578', '0.0.8511081@1775347062.183228731', '0.0.8511579', '5', 'testnet', '2026-04-05T01:57:52.690538');
INSERT INTO hedera_metadata (image_id, file_id, topic_id, topic_tx_id, nft_token_id, nft_serial, network, created_at) VALUES ('e8bdd18d', '0.0.8513638', '0.0.8511578', '0.0.8511081@1775347284.392821311', '0.0.8511579', '6', 'testnet', '2026-04-05T02:01:35.098948');
INSERT INTO hedera_metadata (image_id, file_id, topic_id, topic_tx_id, nft_token_id, nft_serial, network, created_at) VALUES ('0deaec18', '0.0.8513736', '0.0.8511578', '0.0.8511081@1775347812.468875408', '0.0.8511579', '7', 'testnet', '2026-04-05T02:10:23.078811');
INSERT INTO hedera_metadata (image_id, file_id, topic_id, topic_tx_id, nft_token_id, nft_serial, network, created_at) VALUES ('e486c008', '0.0.8513816', '0.0.8511578', '0.0.8511081@1775348236.42875289', '0.0.8511579', '8', 'testnet', '2026-04-05T02:17:28.650370');
INSERT INTO hedera_metadata (image_id, file_id, topic_id, topic_tx_id, nft_token_id, nft_serial, network, created_at) VALUES ('15686b2d', '0.0.8513892', '0.0.8511578', '0.0.8511081@1775348664.698477029', '0.0.8511579', '9', 'testnet', '2026-04-05T02:24:35.983244');

-- ══════════════════════════════════════════════════════
-- FILES ON DISK (for reference — not part of DB)
-- These files exist at API/library/ and are referenced by file_path columns
-- ══════════════════════════════════════════════════════
-- people/usr_alexandra_81702/: 2 files -> selfie_0.jpg, selfie_1.jpg
-- people/usr_german_39107/: 2 files -> selfie_0.jpg, selfie_1.jpg
-- people/usr_german_48869/: 2 files -> selfie_0.jpg, selfie_1.jpg
-- people/usr_josemaria_40346/: 3 files -> selfie_0.jpg, selfie_1.jpg, selfie_2.jpg
-- people/usr_josemaria_5788/: 2 files -> selfie_0.jpg, selfie_1.jpg
-- people/usr_kevin_23788/: 2 files -> selfie_0.jpg, selfie_1.jpg
-- places/place_hall_ethglobal_52568/: 7 files -> photo_0.jpg, photo_1.jpg, photo_2.jpg, photo_3.jpg, photo_4.jpg, photo_5.jpg, photo_6.jpg
-- places/place_hall_ethglobal_6065/: 2 files -> photo_0.jpg, photo_1.jpg
-- objects/obj_agua_67313/: 1 files -> photo_0.jpg
-- objects/obj_agua_75186/: 1 files -> photo_0.jpg
-- objects/obj_agua_con_gas_30771/: 1 files -> photo_0.jpg
-- objects/obj_amaca_14625/: 1 files -> photo_0.jpg
-- objects/obj_amaca_2_55162/: 1 files -> photo_0.jpg
-- objects/obj_amaca_60365/: 1 files -> photo_0.jpg
-- objects/obj_banner_13155/: 1 files -> photo_0.jpg
-- objects/obj_bar_9586/: 1 files -> photo_0.jpg
-- objects/obj_cartel_techo_44058/: 1 files -> photo_0.jpg
-- objects/obj_cojines_69909/: 1 files -> photo_0.jpg
-- objects/obj_columna_5151/: 1 files -> photo_0.jpg
-- objects/obj_decorado_60380/: 1 files -> photo_0.jpg
-- objects/obj_extintor_64578/: 1 files -> photo_0.jpg
-- objects/obj_foco_39855/: 1 files -> photo_0.jpg
-- objects/obj_lampara_93635/: 1 files -> photo_0.jpg
-- objects/obj_laptop_3385/: 1 files -> photo_0.jpg
-- objects/obj_laptop_67979/: 1 files -> photo_0.jpg
-- objects/obj_limpieza_26465/: 1 files -> photo_0.jpg
-- objects/obj_maceta_96703/: 1 files -> photo_0.jpg
-- objects/obj_mesa_38837/: 1 files -> photo_0.jpg
-- objects/obj_mesita_19161/: 1 files -> photo_0.jpg
-- objects/obj_mesita_24092/: 1 files -> photo_0.jpg
-- objects/obj_palmera_92652/: 1 files -> photo_0.jpg
-- objects/obj_papelera_52259/: 1 files -> photo_0.jpg
-- objects/obj_papelera_70368/: 1 files -> photo_0.jpg
-- objects/obj_pasillo_22700/: 1 files -> photo_0.jpg
-- objects/obj_plant_84984/: 1 files -> photo_0.jpg
-- objects/obj_planta_30099/: 1 files -> photo_0.jpg
-- objects/obj_planta_78485/: 1 files -> photo_0.jpg
-- objects/obj_publi_868/: 1 files -> photo_0.jpg
-- objects/obj_rollup_28208/: 1 files -> photo_0.jpg
-- objects/obj_silla_2884/: 1 files -> photo_0.jpg
-- objects/obj_silla_34421/: 1 files -> photo_0.jpg
-- objects/obj_silla_43800/: 1 files -> photo_0.jpg
-- objects/obj_silla_74845/: 1 files -> photo_0.jpg
-- objects/obj_sombrilla_38931/: 1 files -> photo_0.jpg
-- objects/obj_sombrilla_52180/: 1 files -> photo_0.jpg
-- objects/obj_stand_85952/: 1 files -> photo_0.jpg
-- objects/obj_techo_53480/: 1 files -> photo_0.jpg
-- objects/obj_techo_67499/: 1 files -> photo_0.jpg