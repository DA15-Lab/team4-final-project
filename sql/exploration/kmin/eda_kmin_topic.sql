/*
===============================================================================
프로젝트: 익명 투표 SNS 사용자 행동 분석
작성 범위: 2026-08-31 ~ 2026-09-02 개인 EDA

임시 주제
  친구 관계 및 투표 행동과 사용자 활성도·단기 리텐션 간 관계 분석
  - 사용자 행동 퍼널을 통한 주요 이탈 구간 탐색

이 파일의 목적
  1. 탈퇴 사유에서 친구·질문 관련 문제 신호를 확인한다.
  2. 친구 관계와 투표 경험을 사용자 단위 변수로 만들 수 있는지 확인한다.
  3. Votes 행동 결과와 Hackle 행동 과정을 연결할 수 있는지 점검한다.

해석 시 주의사항
  - accounts_userwithdraw에는 user_id가 없어 탈퇴 사유와 개인 행동을 직접
    연결할 수 없다. 탈퇴 사유는 주제 선정의 배경 자료로만 사용한다.
  - accounts_user.ban_status의 W를 탈퇴자로 확정하지 않는다.
  - 열람률·답장률은 분석 대상과 관찰 기간을 정의하기 전까지 최종 퍼널
    전환율로 해석하지 않는다.
  - Hackle 데이터는 2023-07-18 ~ 2023-08-10의 24일만 제공된다.
  - hackle_properties를 원본 상태로 hackle_events에 조인하면 이벤트 행이
    중복 증가할 수 있으므로 세션-사용자 관계를 먼저 정리해야 한다.
===============================================================================
*/


/* ---------------------------------------------------------------------------
01. 탈퇴 및 사용자 상태 확인
목적: 서비스 이탈과 관련된 문제 후보를 찾고, 사용 가능한 이탈 지표의 한계를
      확인한다.
--------------------------------------------------------------------------- */

USE votes;

-- 01-1. 탈퇴 사유별 기록 수와 비율
SELECT
    reason,
    COUNT(*) AS withdraw_count,
    ROUND(
        COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (),
        2
    ) AS percentage
FROM accounts_userwithdraw
GROUP BY reason
ORDER BY withdraw_count DESC;


-- 01-2. 친구 부족·질문 불만족 관련 탈퇴 사유의 합계
-- 확인 결과: 27,583건, 전체 탈퇴 기록의 약 38.98%
SELECT
    COUNT(*) AS total_withdraw_records,
    SUM(
        reason IN ('함께 할 친구가 없어서', '재밌는 질문이 없어서')
    ) AS friend_or_question_reason_count,
    ROUND(
        SUM(reason IN ('함께 할 친구가 없어서', '재밌는 질문이 없어서'))
        * 100.0 / COUNT(*),
        2
    ) AS friend_or_question_reason_rate
FROM accounts_userwithdraw;


-- 01-3. 사용자·탈퇴 기록의 규모와 데이터 기간 비교
SELECT
    'accounts_user' AS table_name,
    COUNT(*) AS total_rows,
    COUNT(created_at) AS non_null_date_rows,
    MIN(created_at) AS start_date,
    MAX(created_at) AS end_date
FROM accounts_user

UNION ALL

SELECT
    'accounts_userwithdraw',
    COUNT(*),
    COUNT(created_at),
    MIN(created_at),
    MAX(created_at)
FROM accounts_userwithdraw;


-- 01-4. 사용자 상태 코드별 분포
-- W 사용자 수와 탈퇴 기록 수가 일치하지 않으므로 W=탈퇴로 확정하지 않는다.
SELECT
    ban_status,
    COUNT(*) AS user_count,
    ROUND(
        COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (),
        2
    ) AS percentage
FROM accounts_user
GROUP BY ban_status
ORDER BY user_count DESC;


-- 01-5. 상태 코드별 사용자 특성 비교
-- 목적: 문서에 정의되지 않은 상태 코드의 성격을 간접적으로 탐색한다.
-- 주의: 아래 결과만으로 상태 코드의 공식 의미를 확정하지 않는다.
SELECT
    ban_status,
    COUNT(*) AS user_count,
    ROUND(AVG(JSON_LENGTH(friend_id_list)), 2) AS avg_friend_count,
    ROUND(AVG(point), 2) AS avg_point,
    ROUND(AVG(report_count), 2) AS avg_report_count,
    SUM(report_count > 0) AS reported_users,
    MIN(created_at) AS first_created_at,
    MAX(created_at) AS last_created_at
FROM accounts_user
GROUP BY ban_status
ORDER BY user_count DESC;


-- 01-6. 상태 코드별 투표 참여 수준 비교
WITH vote_activity AS (
    SELECT
        user_id,
        COUNT(*) AS vote_count,
        MAX(created_at) AS last_vote_at
    FROM accounts_userquestionrecord
    GROUP BY user_id
)
SELECT
    u.ban_status,
    COUNT(*) AS total_users,
    SUM(v.user_id IS NOT NULL) AS users_with_vote,
    ROUND(
        SUM(v.user_id IS NOT NULL) * 100.0 / COUNT(*),
        2
    ) AS voting_user_rate,
    ROUND(AVG(COALESCE(v.vote_count, 0)), 2) AS avg_vote_count,
    MAX(v.last_vote_at) AS latest_vote_at
FROM accounts_user AS u
LEFT JOIN vote_activity AS v
    ON u.id = v.user_id
GROUP BY u.ban_status
ORDER BY total_users DESC;


/* ---------------------------------------------------------------------------
02. 친구 관계 확인
목적: 친구 관계를 사용자별 친구 수와 친구 형성 과정으로 측정할 수 있는지
      확인한다.
--------------------------------------------------------------------------- */

-- 02-1. friend_id_list 저장 형식과 결측·빈 목록 확인
SELECT
    COUNT(*) AS total_users,
    SUM(friend_id_list IS NULL) AS null_count,
    SUM(TRIM(CAST(friend_id_list AS CHAR)) = '') AS empty_string_count,
    SUM(TRIM(CAST(friend_id_list AS CHAR)) = '[]') AS empty_list_count,
    SUM(JSON_VALID(friend_id_list)) AS valid_json_count
FROM accounts_user;


-- 02-2. 사용자별 친구 수 요약
-- 확인 결과: 평균 53.33명, 최소 0명, 최대 1,373명
SELECT
    COUNT(*) AS total_users,
    MIN(JSON_LENGTH(friend_id_list)) AS min_friend_count,
    ROUND(AVG(JSON_LENGTH(friend_id_list)), 2) AS avg_friend_count,
    MAX(JSON_LENGTH(friend_id_list)) AS max_friend_count,
    SUM(JSON_LENGTH(friend_id_list) = 0) AS zero_friend_users
FROM accounts_user;


-- 02-3. 친구 수 구간별 사용자 분포
SELECT
    CASE
        WHEN JSON_LENGTH(friend_id_list) = 0 THEN '0명'
        WHEN JSON_LENGTH(friend_id_list) <= 5 THEN '1~5명'
        WHEN JSON_LENGTH(friend_id_list) <= 10 THEN '6~10명'
        WHEN JSON_LENGTH(friend_id_list) <= 20 THEN '11~20명'
        WHEN JSON_LENGTH(friend_id_list) <= 50 THEN '21~50명'
        WHEN JSON_LENGTH(friend_id_list) <= 100 THEN '51~100명'
        ELSE '101명 이상'
    END AS friend_count_group,
    COUNT(*) AS user_count,
    ROUND(
        COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (),
        2
    ) AS percentage
FROM accounts_user
GROUP BY friend_count_group
ORDER BY FIELD(
    friend_count_group,
    '0명', '1~5명', '6~10명', '11~20명',
    '21~50명', '51~100명', '101명 이상'
);


-- 02-4. 친구 요청 상태별 규모와 발생 기간
-- 명세서 정의: P=대기, A=수락, R=거절
SELECT
    status,
    COUNT(*) AS request_count,
    MIN(created_at) AS first_request_at,
    MAX(created_at) AS last_request_at,
    MIN(updated_at) AS first_updated_at,
    MAX(updated_at) AS last_updated_at
FROM accounts_friendrequest
GROUP BY status
ORDER BY request_count DESC;


-- 02-5. 상태별 친구 요청 발신·수신 사용자 수
SELECT
    status,
    COUNT(DISTINCT send_user_id) AS sending_users,
    COUNT(DISTINCT receive_user_id) AS receiving_users
FROM accounts_friendrequest
GROUP BY status
ORDER BY status;


/* ---------------------------------------------------------------------------
03. 투표 경험 확인
목적: 투표 참여·수신·열람·답장을 사용자 활성화 후보 지표로 만들 수 있는지
      확인한다.
--------------------------------------------------------------------------- */

-- 03-1. 투표 기록의 전체 규모와 기간
SELECT
    COUNT(*) AS total_vote_records,
    COUNT(DISTINCT user_id) AS voting_users,
    COUNT(DISTINCT chosen_user_id) AS chosen_users,
    COUNT(DISTINCT question_id) AS question_count,
    COUNT(DISTINCT question_piece_id) AS question_piece_count,
    MIN(created_at) AS first_vote_at,
    MAX(created_at) AS last_vote_at
FROM accounts_userquestionrecord;


-- 03-2. 투표 상태·답장 상태·열람 여부 조합
-- status: C=닫힘, I=초성 열림, B=차단
-- answer_status: N=미답변, P=비공개, A=공개
SELECT
    status,
    answer_status,
    has_read,
    COUNT(*) AS record_count
FROM accounts_userquestionrecord
GROUP BY
    status,
    answer_status,
    has_read
ORDER BY
    status,
    answer_status,
    has_read;


-- 03-3. 투표자·선택받은 사용자의 accounts_user 연결률
-- 확인 결과: 양쪽 모두 100% 연결
SELECT
    COUNT(*) AS total_vote_records,
    COUNT(voter.id) AS matched_voter_records,
    ROUND(
        COUNT(voter.id) * 100.0 / COUNT(*),
        2
    ) AS voter_match_rate,
    COUNT(chosen.id) AS matched_chosen_records,
    ROUND(
        COUNT(chosen.id) * 100.0 / COUNT(*),
        2
    ) AS chosen_match_rate
FROM accounts_userquestionrecord AS v
LEFT JOIN accounts_user AS voter
    ON v.user_id = voter.id
LEFT JOIN accounts_user AS chosen
    ON v.chosen_user_id = chosen.id;


/* ---------------------------------------------------------------------------
04. Hackle 이벤트 구조 확인
목적: 행동 퍼널·세션·단기 리텐션 분석이 가능한지, 그리고 조인 전에 어떤
      전처리가 필요한지 확인한다.
--------------------------------------------------------------------------- */

USE hackle;

-- 04-1. 이벤트 테이블의 규모·키·세션·기간 확인
SELECT
    COUNT(*) AS total_event_rows,
    COUNT(event_id) - COUNT(DISTINCT event_id) AS duplicate_event_id_rows,
    SUM(event_id IS NULL) AS null_event_id_rows,
    COUNT(DISTINCT session_id) AS distinct_session_count,
    SUM(session_id IS NULL) AS null_session_rows,
    MIN(event_datetime) AS first_event_at,
    MAX(event_datetime) AS last_event_at
FROM hackle_events;


-- 04-2. 속성 테이블의 세션·사용자 기준 중복 구조 확인
-- 주의: extra_property_rows는 정확히 동일한 행의 중복 수가 아니라,
--       세션당 한 행을 초과하여 저장된 행의 수이다.
SELECT
    COUNT(*) AS property_rows,
    COUNT(DISTINCT session_id) AS distinct_session_count,
    COUNT(*) - COUNT(DISTINCT session_id) AS extra_property_rows,
    SUM(session_id IS NULL) AS null_session_rows,
    COUNT(DISTINCT user_id) AS distinct_user_count,
    SUM(user_id IS NULL) AS null_user_rows
FROM hackle_properties;


-- 04-3. 이벤트별 발생 건수·발생 세션 수·기간 확인
SELECT
    event_key,
    COUNT(*) AS event_count,
    COUNT(DISTINCT session_id) AS session_count,
    MIN(event_datetime) AS first_event_at,
    MAX(event_datetime) AS last_event_at
FROM hackle_events
GROUP BY event_key
ORDER BY event_count DESC;


-- 04-4. events와 properties의 session_id 집합 연결 범위 확인
WITH event_sessions AS (
    SELECT DISTINCT session_id
    FROM hackle_events
),
property_sessions AS (
    SELECT DISTINCT session_id
    FROM hackle_properties
)
SELECT
    (SELECT COUNT(*) FROM event_sessions) AS event_session_count,
    (SELECT COUNT(*) FROM property_sessions) AS property_session_count,
    (
        SELECT COUNT(*)
        FROM event_sessions AS e
        LEFT JOIN property_sessions AS p
            ON e.session_id = p.session_id
        WHERE p.session_id IS NULL
    ) AS event_only_sessions,
    (
        SELECT COUNT(*)
        FROM property_sessions AS p
        LEFT JOIN event_sessions AS e
            ON p.session_id = e.session_id
        WHERE e.session_id IS NULL
    ) AS property_only_sessions;


-- 04-5. 세션당 속성 행·사용자·기기 수 확인
WITH session_profile AS (
    SELECT
        session_id,
        COUNT(*) AS property_row_count,
        COUNT(DISTINCT user_id) AS user_count,
        COUNT(DISTINCT device_id) AS device_count
    FROM hackle_properties
    GROUP BY session_id
)
SELECT
    COUNT(*) AS total_sessions,
    SUM(property_row_count = 1) AS one_property_row_sessions,
    SUM(property_row_count > 1) AS multiple_property_row_sessions,
    MAX(property_row_count) AS max_property_rows_per_session,
    SUM(user_count = 1) AS one_user_sessions,
    SUM(user_count > 1) AS multiple_user_sessions,
    MAX(user_count) AS max_users_per_session,
    SUM(device_count > 1) AS multiple_device_sessions
FROM session_profile;


-- 04-6. 사용자 ID가 여러 개인 세션 사례 확인
SELECT
    session_id,
    COUNT(*) AS property_row_count,
    COUNT(DISTINCT user_id) AS user_count,
    COUNT(DISTINCT device_id) AS device_count,
    GROUP_CONCAT(
        DISTINCT CAST(user_id AS CHAR)
        ORDER BY CAST(user_id AS CHAR)
        SEPARATOR ', '
    ) AS user_id_list
FROM hackle_properties
GROUP BY session_id
HAVING COUNT(DISTINCT user_id) > 1
ORDER BY user_count DESC, property_row_count DESC
LIMIT 20;


