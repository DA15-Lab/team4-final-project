WITH UserVoteStats AS (
     SELECT chosen_user_id AS user_id,
            COUNT(id) AS received_votes
     FROM accounts_userquestionrecord
     GROUP BY chosen_user_id),
     UserFriendStats AS (
     SELECT id AS user_id,
            (LENGTH(friend_id_list) - LENGTH(REPLACE(friend_id_list, ',', ''))) + 1 AS friend_count
     FROM accounts_user
     WHERE friend_id_list IS NOT NULL AND friend_id_list != '[]' 
           AND friend_id_list != ''),
     CuriosityIndexData AS (
     SELECT f.user_id, f.friend_count, v.received_votes,
            (CAST(v.received_votes AS DECIMAL(10, 2)) / f.friend_count) AS curiosity_index,
            CASE WHEN f.friend_count < 10 THEN '1. Low-Tier (아싸)'
                 WHEN f.friend_count <= 40 THEN '2. Mid-Tier (중간층)'
                 ELSE '3. High-Tier (인싸)' END AS tier
     FROM UserFriendStats f
     JOIN UserVoteStats v ON f.user_id = v.user_id
     WHERE f.friend_count > 0 AND v.received_votes > 0)

SELECT tier AS '유저 그룹(Tier)', COUNT(user_id) AS '유저 수',
       ROUND(AVG(curiosity_index), 3) AS '평균 호기심 지수',
       MAX(curiosity_index) AS '최대 호기심 지수'
FROM CuriosityIndexData
GROUP BY tier
ORDER BY tier;

---

WITH UserFriendStats AS (
    -- 1. 친구 수 계산
    SELECT 
        id AS user_id,
        (LENGTH(friend_id_list) - LENGTH(REPLACE(friend_id_list, ',', ''))) + 1 AS friend_count
    FROM accounts_user
    WHERE friend_id_list IS NOT NULL 
      AND friend_id_list != '[]' 
      AND friend_id_list != ''
),
UserVoteStats AS (
    -- 2. 받은 투표 수 집계
    SELECT 
        chosen_user_id AS user_id,
        COUNT(id) AS received_votes
    FROM accounts_userquestionrecord
    GROUP BY chosen_user_id
),
UserPointStats AS (
    -- 3. 소모한 포인트 집계 (결제/패닉 소비 확인용)
    SELECT 
        user_id,
        SUM(ABS(delta_point)) AS total_spent
    FROM accounts_pointhistory
    WHERE delta_point < 0
    GROUP BY user_id
)
-- 4. 3가지 데이터를 하나로 병합 (유저 단위 요약본)
SELECT 
    f.user_id,
    f.friend_count,
    COALESCE(v.received_votes, 0) AS received_votes,
    COALESCE(p.total_spent, 0) AS total_spent
FROM UserFriendStats f
JOIN UserVoteStats v ON f.user_id = v.user_id
LEFT JOIN UserPointStats p ON f.user_id = p.user_id
WHERE f.friend_count > 0 AND v.received_votes > 0;

---

WITH MidTierUsers AS (
    -- 1. K-Means 결과를 바탕으로 Mid-Tier 유저만 필터링
    SELECT 
        id AS user_id
    FROM accounts_user
    WHERE (LENGTH(friend_id_list) - LENGTH(REPLACE(friend_id_list, ',', ''))) + 1 BETWEEN 11 AND 340
      AND friend_id_list IS NOT NULL 
      AND friend_id_list != '[]' 
      AND friend_id_list != ''
)
-- 2. 포인트 사용 기록, 투표 기록, 질문 내용을 조인하여 텍스트별 매출 기여도 집계
SELECT 
    q.question_text AS '질문 내용(question_text)',
    COUNT(DISTINCT p.user_id) AS '지갑을 연 유저 수',
    SUM(ABS(p.delta_point)) AS '총 소모 포인트',
    ROUND(SUM(ABS(p.delta_point)) / COUNT(DISTINCT p.user_id), 0) AS '1인당 평균 소모 포인트'
FROM accounts_pointhistory p
JOIN accounts_userquestionrecord uqr ON p.user_question_record_id = uqr.id
JOIN polls_question q ON uqr.question_id = q.id
JOIN MidTierUsers m ON p.user_id = m.user_id
WHERE p.delta_point < 0 -- 포인트 차감(사용) 기록만 추출
GROUP BY q.question_text
ORDER BY SUM(ABS(p.delta_point)) DESC;

---

WITH MidTierUsers AS (
    -- 1. Mid-Tier (친구 수 11~340명) 유저 필터링
    SELECT 
        id AS user_id
    FROM accounts_user
    WHERE (LENGTH(friend_id_list) - LENGTH(REPLACE(friend_id_list, ',', ''))) + 1 BETWEEN 11 AND 340
      AND friend_id_list IS NOT NULL 
      AND friend_id_list != '[]' 
      AND friend_id_list != ''
),
QuestionExposure AS (
    -- 2. 유저가 받은 질문 기록에 순번 매기기 (이 질문을 몇 번째 받는 것인가?)
    SELECT 
        uqr.id AS record_id,
        uqr.chosen_user_id AS user_id,
        uqr.question_id,
        uqr.opened_times, -- 힌트를 열어본 횟수 (과금 의지)
        ROW_NUMBER() OVER(PARTITION BY uqr.chosen_user_id, uqr.question_id ORDER BY uqr.created_at ASC) AS exposure_nth
    FROM accounts_userquestionrecord uqr
    JOIN MidTierUsers m ON uqr.chosen_user_id = m.user_id
)
-- 3. 질문 중복(노출 횟수)에 따른 포인트 사용(결제) 지표 집계
SELECT 
    CASE 
        WHEN exposure_nth = 1 THEN '1. 해당 질문 최초 수신 (신선함)'
        WHEN exposure_nth = 2 THEN '2. 2번째 중복 수신'
        WHEN exposure_nth = 3 THEN '3. 3번째 중복 수신'
        ELSE '4. 4번 이상 극강의 중복 수신 (피로도 MAX)'
    END AS '질문 중복 상태',
    COUNT(record_id) AS '총 수신된 투표 건수',
    SUM(CASE WHEN opened_times > 0 THEN 1 ELSE 0 END) AS '초성 힌트를 열어본 건수(과금)',
    ROUND(
        SUM(CASE WHEN opened_times > 0 THEN 1 ELSE 0 END) / COUNT(record_id) * 100, 
        2
    ) AS '과금 전환율(CVR %)'
FROM QuestionExposure
GROUP BY 
    CASE 
        WHEN exposure_nth = 1 THEN '1. 해당 질문 최초 수신 (신선함)'
        WHEN exposure_nth = 2 THEN '2. 2번째 중복 수신'
        WHEN exposure_nth = 3 THEN '3. 3번째 중복 수신'
        ELSE '4. 4번 이상 극강의 중복 수신 (피로도 MAX)'
    END
ORDER BY 1;

---

SELECT 
    CASE phone_type 
        WHEN 'A' THEN 'Android (안드로이드)' 
        WHEN 'I' THEN 'iOS (아이폰)' 
        ELSE phone_type 
    END AS '운영체제(OS)',
    COUNT(id) AS '총 결제 시도(실패) 건수',
    SUM(CASE WHEN productId IS NULL THEN 1 ELSE 0 END) AS '상품ID 누락(NULL) 건수',
    ROUND(SUM(CASE WHEN productId IS NULL THEN 1 ELSE 0 END) / COUNT(id) * 100, 2) AS '누락 발생률(%)'
FROM accounts_failpaymenthistory
GROUP BY phone_type
ORDER BY '누락 발생률(%)' DESC;

---

WITH UserFriendStats AS (
    -- 1. 유저별 친구 수 계산
    SELECT 
        id AS user_id,
        (LENGTH(friend_id_list) - LENGTH(REPLACE(friend_id_list, ',', ''))) + 1 AS friend_count
    FROM accounts_user
    WHERE friend_id_list IS NOT NULL 
      AND friend_id_list != '[]' 
      AND friend_id_list != ''
),
MidTierUsers AS (
    -- 2. 핵심 타겟인 Mid-Tier(중간층) 유저만 필터링
    SELECT user_id
    FROM UserFriendStats
    WHERE friend_count BETWEEN 11 AND 340
)
-- 3. Mid-Tier 유저들의 OS별 결제 실패 내역과 유실 매출 추산
SELECT 
    CASE f.phone_type 
        WHEN 'A' THEN 'Android' 
        WHEN 'I' THEN 'iOS' 
    END AS '운영체제(OS)',
    COUNT(DISTINCT f.user_id) AS '결제를 시도했던 Mid-Tier 유저 수',
    COUNT(f.id) AS '결제 실패 건수',
    SUM(CASE WHEN f.productId IS NULL THEN 1 ELSE 0 END) AS 'iOS 치명적 에러(NULL) 건수',
    -- 에러(NULL) 1건당 가장 인기 있는 777포인트를 구매하려 했다고 가정하여 손실액 계산
    SUM(CASE WHEN f.productId IS NULL THEN 777 ELSE 0 END) AS '증발한 예상 포인트(하트) 손실액'
FROM accounts_failpaymenthistory f
JOIN MidTierUsers m ON f.user_id = m.user_id
GROUP BY f.phone_type;

---

WITH ShopFunnel AS (
    -- 1. 세션 내 상점 진입 여부와 실제 구매 완료 여부 파악
    SELECT 
        session_id,
        MAX(CASE WHEN event_key = 'view_shop' THEN 1 ELSE 0 END) AS is_viewed,
        MAX(CASE WHEN event_key = 'complete_purchase' THEN 1 ELSE 0 END) AS is_purchased
    FROM hackle_events
    GROUP BY session_id
),
WindowShopperSessions AS (
    -- 2. 상점은 들어갔으나(is_viewed = 1) 구매하지 않고 나간(is_purchased = 0) 세션 추출
    SELECT session_id
    FROM ShopFunnel
    WHERE is_viewed = 1 AND is_purchased = 0
)
-- 3. 핵클 프로퍼티(hackle_properties)와 조인하여 유저 ID 매핑 후 집계
SELECT 
    COUNT(DISTINCT w.session_id) AS '이탈한 윈도우 쇼퍼 세션 수',
    COUNT(DISTINCT hp.user_id) AS '이탈한 고유 유저 수',
    COUNT(h.id) AS '상점 관련 총 이벤트 발생 건수'
FROM WindowShopperSessions w
JOIN hackle_events h ON w.session_id = h.session_id
LEFT JOIN hackle_properties hp ON w.session_id = hp.session_id;

---

WITH UserShopBehavior AS (
    -- 1. 유저별(hackle_properties 기준)로 상점 진입 횟수와 구매 완료 여부 집계
    SELECT 
        hp.user_id,
        SUM(CASE WHEN he.event_key = 'view_shop' THEN 1 ELSE 0 END) AS view_shop_count,
        MAX(CASE WHEN he.event_key = 'complete_purchase' THEN 1 ELSE 0 END) AS has_purchased
    FROM hackle_events he
    JOIN hackle_properties hp ON he.session_id = hp.session_id
    WHERE hp.user_id REGEXP '^[0-9]+$' -- 숫자 형태의 정상 유저 ID만 필터링
    GROUP BY hp.user_id
)
-- 2. 상점은 들어갔으나(view_shop_count > 0) 구매 이력이 없는(has_purchased = 0) 윈도우 쇼퍼들의 '재방문 횟수별' 규모 집계
SELECT 
    CASE 
        WHEN view_shop_count = 1 THEN '1회만 구경하고 이탈'
        WHEN view_shop_count BETWEEN 2 AND 3 THEN '2~3회 반복 구경 후 이탈'
        WHEN view_shop_count BETWEEN 4 AND 10 THEN '4~10회 고관여 윈도우 쇼퍼'
        ELSE '10회 이상 상점 상주형 쇼퍼'
    END AS '상점 재방문 성향',
    COUNT(user_id) AS '유저 수',
    SUM(view_shop_count) AS '해당 그룹의 총 상점 진입 횟수'
FROM UserShopBehavior
WHERE view_shop_count > 0 AND has_purchased = 0
GROUP BY 1
ORDER BY 2 DESC;

---

SELECT 
    CASE phone_type
        WHEN 'A' THEN 'Android (정상 결제 환경)' 
        WHEN 'I' THEN 'iOS (상품ID 누락 에러 환경)' 
        ELSE phone_type 
    END AS '운영체제(OS)',
    COUNT(id) AS '총 결제 시도 실패 건수',
    SUM(CASE WHEN productId IS NULL THEN 1 ELSE 0 END) AS '상품ID가 NULL로 증발한 건수',
    ROUND(SUM(CASE WHEN productId IS NULL THEN 1 ELSE 0 END) / COUNT(id) * 100, 2) AS '에러 발생률(%)'
FROM accounts_failpaymenthistory
GROUP BY phone_type;

---

WITH IOSFailedUsers AS (
    SELECT DISTINCT user_id
    FROM accounts_failpaymenthistory
    WHERE phone_type = 'I' AND productId IS NULL
),
UserVoteStats AS (
    SELECT 
        chosen_user_id AS user_id,
        COUNT(id) AS received_votes
    FROM accounts_userquestionrecord
    GROUP BY chosen_user_id
),
UserShopVisits AS (
    SELECT 
        hp.user_id,
        COUNT(he.id) AS shop_visit_count
    FROM hackle_events he
    JOIN hackle_properties hp ON he.session_id = hp.session_id
    WHERE he.event_key = 'view_shop' AND hp.user_id REGEXP '^[0-9]+$'
    GROUP BY hp.user_id
)
SELECT 
    CASE 
        WHEN COALESCE(v.received_votes, 0) >= 5 OR COALESCE(s.shop_visit_count, 0) >= 2 
            THEN 'A. 관심 및 참여 유저 (투표 5개 이상 OR 상점 방문 2회 이상)'
        ELSE 'B. 무활동/이탈 유저'
    END AS '결제 에러 유저의 성향 분류',
    COUNT(i.user_id) AS '해당 유저 수',
    ROUND(AVG(COALESCE(v.received_votes, 0)), 1) AS '그룹 평균 받은 투표 수',
    ROUND(AVG(COALESCE(s.shop_visit_count, 0)), 1) AS '그룹 평균 상점 진입 횟수'
FROM IOSFailedUsers i
LEFT JOIN UserVoteStats v ON i.user_id = v.user_id
LEFT JOIN UserShopVisits s ON i.user_id = s.user_id
GROUP BY 1
ORDER BY 2 DESC;

---

WITH QuestionExposure AS (
    -- 1. 유저가 받은 질문 기록에 순번(몇 번째 수신인지) 매기기
    SELECT 
        uqr.id AS record_id,
        uqr.chosen_user_id AS user_id,
        uqr.question_id,
        qp.is_skipped, -- 스킵 여부
        ROW_NUMBER() OVER(PARTITION BY uqr.chosen_user_id, uqr.question_id ORDER BY uqr.created_at ASC) AS exposure_nth
    FROM accounts_userquestionrecord uqr
    JOIN polls_questionpiece qp ON uqr.question_piece_id = qp.id
)
-- 2. 질문 중복 수신 횟수별 스킵률(Skip Rate) 집계
SELECT 
    CASE 
        WHEN exposure_nth = 1 THEN '1회 수신 (최초/신선함)'
        WHEN exposure_nth = 2 THEN '2회 중복 수신'
        WHEN exposure_nth = 3 THEN '3회 중복 수신'
        ELSE '4회 이상 극심한 피로도 누적'
    END AS '질문 중복 노출 단계',
    COUNT(record_id) AS '총 노출 횟수',
    SUM(CASE WHEN is_skipped = 1 THEN 1 ELSE 0 END) AS '스킵(Skip)된 횟수',
    ROUND(SUM(CASE WHEN is_skipped = 1 THEN 1 ELSE 0 END) / COUNT(record_id) * 100, 2) AS '스킵률(Skip Rate %)'
FROM QuestionExposure
GROUP BY 1
ORDER BY 1;

---

WITH QuestionExposure AS (
    -- 1. 유저별 동일 질문 수신 순번(Exposure Nth) 계산
    SELECT 
        uqr.id AS record_id,
        uqr.chosen_user_id AS user_id,
        uqr.question_id,
        uqr.question_piece_id,
        uqr.created_at,
        ROW_NUMBER() OVER(PARTITION BY uqr.chosen_user_id, uqr.question_id ORDER BY uqr.created_at ASC) AS exposure_nth
    FROM accounts_userquestionrecord uqr
),
DuplicateExposures AS (
    -- 2. 2회 이상 중복 수신된 질문 기록 추출
    SELECT 
        qe.user_id,
        qe.question_id,
        qe.created_at,
        qe.exposure_nth,
        qe.record_id
    FROM QuestionExposure qe
    WHERE qe.exposure_nth > 1
),
UserSessionCheck AS (
    -- 3. 중복 질문 시점의 세션 매핑 및 완주 여부 확인
    SELECT 
        de.user_id,
        de.exposure_nth,
        hp.session_id,
        CASE WHEN he.event_key = 'complete_question' THEN 1 ELSE 0 END AS is_completed_event
    FROM DuplicateExposures de
    JOIN hackle_properties hp ON de.user_id = hp.user_id
    JOIN hackle_events he ON hp.session_id = he.session_id
),
SessionAgg AS (
    -- 4. 세션 단위로 완주 여부 확정
    SELECT 
        user_id,
        exposure_nth,
        session_id,
        MAX(is_completed_event) AS is_completed
    FROM UserSessionCheck
    GROUP BY user_id, exposure_nth, session_id
),
FlattenedStatus AS (
    -- 5. exposure_nth 숫자를 여기서 완전히 문자열 그룹으로 변환
    SELECT 
        session_id,
        CASE 
            WHEN exposure_nth = 2 THEN '2회 중복 수신'
            ELSE '3회 이상 중복 수신'
        END AS exposure_group,
        CASE 
            WHEN is_completed = 1 THEN '질문 세트 완주 (투표 완료)'
            ELSE '중도 이탈 및 앱 종료 (Drop-off)'
        END AS session_status
    FROM SessionAgg
),
GroupedSummary AS (
    -- 6. 숫자 값이 완전히 사라진 문자열(exposure_group, session_status) 기준으로만 완벽히 집계
    SELECT 
        exposure_group,
        session_status,
        COUNT(DISTINCT session_id) AS total_sessions
    FROM FlattenedStatus
    GROUP BY exposure_group, session_status
),
TotalPerGroup AS (
    -- 7. 그룹별 전체 세션 수
    SELECT 
        exposure_group,
        SUM(total_sessions) AS group_total
    FROM GroupedSummary
    GROUP BY exposure_group
)
-- 8. 최종 출력 (2회, 3회 이상 각각 완주/이탈 총 4줄로 깔끔하게 요약)
SELECT 
    g.exposure_group AS '중복 노출 강도',
    g.session_status AS '세션 종료 상태',
    g.total_sessions AS '세션 수',
    ROUND(g.total_sessions * 100.0 / t.group_total, 2) AS '비율(%)'
FROM GroupedSummary g
JOIN TotalPerGroup t ON g.exposure_group = t.exposure_group
ORDER BY g.exposure_group DESC, g.total_sessions DESC;

---

WITH TargetSessions AS (
    -- 1. 전체 데이터 정렬을 피하기 위해, 상점에 진입한 세션만 먼저 가볍게 추출
    SELECT DISTINCT session_id 
    FROM hackle_events 
    WHERE event_key = 'view_shop'
),
FilteredEvents AS (
    -- 2. 추출된 세션들의 데이터만 JOIN으로 가져와서 직전 이벤트(LAG) 계산
    -- (전체 테이블 정렬이 아닌 소규모 정렬이므로 속도가 비약적으로 빠름)
    SELECT 
        h.session_id,
        h.event_key,
        LAG(h.event_key) OVER (PARTITION BY h.session_id ORDER BY h.event_datetime ASC) AS prev_event_key
    FROM hackle_events h
    INNER JOIN TargetSessions ts ON h.session_id = ts.session_id
)
-- 3. 'view_shop' 이벤트가 발생한 시점의 '직전 이벤트(prev_event_key)'만 집계
SELECT 
    COALESCE(prev_event_key, '직전 이벤트 없음 (앱 켜자마자 진입)') AS '상점 진입 직전 이벤트',
    COUNT(session_id) AS '세션 수',
    ROUND(COUNT(session_id) * 100.0 / (SELECT COUNT(*) FROM FilteredEvents WHERE event_key = 'view_shop'), 2) AS '비율(%)'
FROM FilteredEvents
WHERE event_key = 'view_shop'
GROUP BY prev_event_key
ORDER BY 2 DESC
LIMIT 10;

---

WITH UserFailCounts AS (
    -- 1. 유저별 전체 결제 실패(시도) 횟수 집계
    SELECT 
        user_id,
        COUNT(id) AS fail_count
    FROM accounts_failpaymenthistory
    GROUP BY user_id
)
-- 2. 실패 횟수 구간별 유저 모수 파악
SELECT 
    CASE 
        WHEN fail_count = 1 THEN '1. 1회 실패 (단순 변심/취소 가능성)'
        WHEN fail_count = 2 THEN '2. 2회 반복 실패'
        WHEN fail_count >= 3 THEN '3. 3회 이상 반복 실패 (초고관여/강력한 결제 의지)'
    END AS '결제 시도(실패) 횟수',
    COUNT(user_id) AS '해당 유저 수',
    ROUND(COUNT(user_id) * 100.0 / (SELECT COUNT(*) FROM UserFailCounts), 2) AS '비율(%)'
FROM UserFailCounts
GROUP BY 1
ORDER BY 1;

---

WITH UserSignup AS (
    -- 유저의 가입일시 조회 (프로젝트 내 유저 테이블명에 맞게 조정 필요, 예: accounts_user)
    SELECT id AS user_id, created_at AS signup_at
    FROM accounts_user
),
QuestionExposure AS (
    -- 유저별 동일 질문 수신 순번(Exposure Nth) 계산
    SELECT 
        uqr.chosen_user_id AS user_id,
        uqr.question_id,
        uqr.created_at AS exposure_at,
        ROW_NUMBER() OVER(PARTITION BY uqr.chosen_user_id, uqr.question_id ORDER BY uqr.created_at ASC) AS exposure_nth
    FROM accounts_userquestionrecord uqr
),
FirstDuplicate AS (
    -- 각 유저가 '최초로' 중복 질문(exposure_nth = 2)을 마주한 시점
    SELECT 
        user_id,
        MIN(exposure_at) AS first_duplicate_at
    FROM QuestionExposure
    WHERE exposure_nth = 2
    GROUP BY user_id
),
UserDelay AS (
    -- 가입일시와 첫 중복 질문 시점 간의 경과 일수 계산
    SELECT 
        us.user_id,
        DATEDIFF(fd.first_duplicate_at, us.signup_at) AS days_from_signup
    FROM UserSignup us
    JOIN FirstDuplicate fd ON us.user_id = fd.user_id
    WHERE fd.first_duplicate_at >= us.signup_at
)
-- 경과 일수별 누적 유저 비율(CDF) 산출하여 50% 지점 확인
SELECT 
    days_from_signup AS '가입 후 경과 일수',
    COUNT(user_id) AS '해당 일수 도달 유저 수',
    SUM(COUNT(user_id)) OVER(ORDER BY days_from_signup) AS '누적 유저 수',
    ROUND(SUM(COUNT(user_id)) OVER(ORDER BY days_from_signup) * 100.0 / (SELECT COUNT(DISTINCT user_id) FROM UserDelay), 2) AS '누적 유저 비율(%)'
FROM UserDelay
GROUP BY days_from_signup
ORDER BY days_from_signup;