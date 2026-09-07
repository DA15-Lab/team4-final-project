SELECT 
    DATE_FORMAT(created_at, '%Y-%m') AS '가입 월',
    COUNT(id) AS '신규 가입자 수',
    ROUND(AVG(is_push_on) * 100, 2) AS '푸시 알림 허용률(%)'
FROM accounts_user
WHERE is_staff = 0 AND is_superuser = 0
GROUP BY 1
ORDER BY 1;

WITH UserVotes AS (
    SELECT 
        u.id AS user_id,
        COUNT(uqr.id) AS vote_count
    FROM accounts_user u
    LEFT JOIN accounts_userquestionrecord uqr ON u.id = uqr.chosen_user_id
    WHERE u.is_staff = 0 AND u.is_superuser = 0
    GROUP BY u.id
)
SELECT 
    CASE 
        WHEN vote_count = 0 THEN '1. 0표 '
        WHEN vote_count BETWEEN 1 AND 5 THEN '2. 1~5표'
        WHEN vote_count BETWEEN 6 AND 20 THEN '3. 6~20표'
        WHEN vote_count BETWEEN 21 AND 50 THEN '4. 21~50표'
        ELSE '5. 51표 이상'
    END AS '투표 수신 구간',
    COUNT(user_id) AS '유저 수',
    ROUND(COUNT(user_id) / (SELECT COUNT(*) FROM UserVotes) * 100, 2) AS '비율(%)'
FROM UserVotes
GROUP BY 1
ORDER BY 1;

SELECT 
    CASE 
        WHEN delta_point > 0 THEN '포인트 획득 (무료/결제)'
        WHEN delta_point < 0 THEN '포인트 소모 (힌트 오픈 등)'
        ELSE '변동 없음'
    END AS '거래 유형',
    COUNT(id) AS '발생 건수',
    SUM(ABS(delta_point)) AS '총 포인트 볼륨',
    ROUND(AVG(ABS(delta_point)), 0) AS '1회 평균 변동량'
FROM accounts_pointhistory
GROUP BY 1
ORDER BY 3 DESC;

SELECT 
    COUNT(DISTINCT u.id) AS '총 누적 가입자 수',
    
    -- 전체 D+1 평균 리텐션
    ROUND(COUNT(DISTINCT CASE WHEN DATEDIFF(DATE(p.created_at), DATE(u.created_at)) = 1 THEN u.id END) / COUNT(DISTINCT u.id) * 100, 2) AS '전체 평균 D+1 리텐션(%)',
    
    -- 전체 D+3 평균 리텐션
    ROUND(COUNT(DISTINCT CASE WHEN DATEDIFF(DATE(p.created_at), DATE(u.created_at)) = 3 THEN u.id END) / COUNT(DISTINCT u.id) * 100, 2) AS '전체 평균 D+3 리텐션(%)',
    
    -- 전체 D+7 평균 리텐션
    ROUND(COUNT(DISTINCT CASE WHEN DATEDIFF(DATE(p.created_at), DATE(u.created_at)) = 7 THEN u.id END) / COUNT(DISTINCT u.id) * 100, 2) AS '전체 평균 D+7 리텐션(%)'

FROM accounts_user u
LEFT JOIN accounts_pointhistory p ON u.id = p.user_id
WHERE u.is_staff = 0 AND u.is_superuser = 0;

SELECT 
    '2023년 5월 코호트' AS '가입 월',
    COUNT(DISTINCT u.id) AS '5월 총 가입자 수',
    
    ROUND(COUNT(DISTINCT CASE WHEN DATEDIFF(DATE(p.created_at), DATE(u.created_at)) = 1 THEN u.id END) / COUNT(DISTINCT u.id) * 100, 2) AS 'D+1 리텐션(%)',
    
    ROUND(COUNT(DISTINCT CASE WHEN DATEDIFF(DATE(p.created_at), DATE(u.created_at)) = 3 THEN u.id END) / COUNT(DISTINCT u.id) * 100, 2) AS 'D+3 리텐션(%)',
    
    ROUND(COUNT(DISTINCT CASE WHEN DATEDIFF(DATE(p.created_at), DATE(u.created_at)) = 7 THEN u.id END) / COUNT(DISTINCT u.id) * 100, 2) AS 'D+7 리텐션(%)'

FROM accounts_user u
LEFT JOIN accounts_pointhistory p ON u.id = p.user_id
WHERE u.is_staff = 0 AND u.is_superuser = 0
  AND u.created_at >= '2023-05-01 00:00:00' 
  AND u.created_at < '2023-06-01 00:00:00';
  
  WITH UserSpend AS (
    SELECT 
        user_id,
        SUM(ABS(delta_point)) AS total_spent
    FROM accounts_pointhistory
    WHERE delta_point < 0
    GROUP BY user_id
),
RankedSpend AS (
    SELECT 
        user_id,
        total_spent,
        NTILE(100) OVER (ORDER BY total_spent DESC) AS percentile_rank
    FROM UserSpend
)
SELECT 
    CASE 
        WHEN percentile_rank = 1 THEN '1. 상위 1% (초고과금 고래 유저)'
        WHEN percentile_rank BETWEEN 2 AND 10 THEN '2. 상위 2~10% (중과금 유저)'
        ELSE '3. 하위 90% (일반 유저)'
    END AS '유저 등급',
    COUNT(user_id) AS '해당 등급 유저 수',
    SUM(total_spent) AS '총 소모 포인트 (매출 볼륨)',
    ROUND(SUM(total_spent) / (SELECT SUM(total_spent) FROM UserSpend) * 100, 2) AS '전체 매출 점유율(%)',
    ROUND(AVG(total_spent), 0) AS '1인당 평균 결제액'
FROM RankedSpend
GROUP BY 1
ORDER BY 1;

SELECT 
    CASE 
        WHEN u.point < 300 THEN '빈털터리 이탈'
        WHEN u.point BETWEEN 300 AND 999 THEN '애매한 잔액 이탈'
        ELSE '3. 부유한 이탈 (포인트가 남아도 쓸 곳이나 의지 없음)'
    END AS '잔여 포인트 구간',
    COUNT(u.id) AS '0표 이탈 유저 수',
    ROUND(COUNT(u.id) / (SELECT COUNT(u2.id) FROM accounts_user u2 LEFT JOIN accounts_userquestionrecord uqr2 ON u2.id = uqr2.chosen_user_id WHERE u2.is_staff = 0 AND u2.is_superuser = 0 AND uqr2.chosen_user_id IS NULL) * 100, 2) AS '비율(%)'
FROM accounts_user u
LEFT JOIN (
    SELECT DISTINCT chosen_user_id
    FROM accounts_userquestionrecord
) uqr ON u.id = uqr.chosen_user_id
WHERE u.is_staff = 0 AND u.is_superuser = 0
  AND uqr.chosen_user_id IS NULL -- 단 1표도 받지 못한(이탈 의심) 유저만 타겟팅
GROUP BY 1
ORDER BY 1;

SELECT 
    CASE 
        WHEN p.user_id IS NOT NULL THEN '1. 억울한 이탈 (본인은 활동/투표했으나 0표 받은 유저)'
        ELSE '2. 무활동 이탈 (가입 후 아무 활동 없이 0표 받은 유저)'
    END AS '이탈 원인 유형',
    COUNT(DISTINCT u.id) AS '유저 수',
    ROUND(COUNT(DISTINCT u.id) / (SELECT COUNT(u2.id) FROM accounts_user u2 LEFT JOIN accounts_userquestionrecord uqr2 ON u2.id = uqr2.chosen_user_id WHERE u2.is_staff = 0 AND u2.is_superuser = 0 AND uqr2.chosen_user_id IS NULL) * 100, 2) AS '비율(%)'
FROM accounts_user u
LEFT JOIN (
    SELECT DISTINCT chosen_user_id
    FROM accounts_userquestionrecord
) uqr ON u.id = uqr.chosen_user_id
LEFT JOIN (
    -- 한 번이라도 포인트 변동(활동)이 있었던 유저 축출
    SELECT DISTINCT user_id
    FROM accounts_pointhistory
) p ON u.id = p.user_id
WHERE u.is_staff = 0 AND u.is_superuser = 0
  AND uqr.chosen_user_id IS NULL
GROUP BY 1
ORDER BY 1;

SELECT 
    COUNT(u.id) AS '전체 일반 유저 수',
    SUM(CASE WHEN uqr.received_votes IS NULL THEN 1 ELSE 0 END) AS '0표 받은 유저 수',
    ROUND(SUM(CASE WHEN uqr.received_votes IS NULL THEN 1 ELSE 0 END) / COUNT(u.id) * 100, 2) AS '소외 유저 비율(%)'
FROM accounts_user u
LEFT JOIN (
    SELECT chosen_user_id, COUNT(id) AS received_votes
    FROM accounts_userquestionrecord
    GROUP BY chosen_user_id
) uqr ON u.id = uqr.chosen_user_id
WHERE u.is_staff = 0 AND u.is_superuser = 0; -- 관리자 계정 제외

WITH UserVoteCounts AS (
    SELECT 
        u.id AS user_id,
        COUNT(uqr.id) AS vote_count
    FROM accounts_user u
    LEFT JOIN accounts_userquestionrecord uqr ON u.id = uqr.chosen_user_id
    WHERE u.is_staff = 0 AND u.is_superuser = 0
    GROUP BY u.id
),
RankedUsers AS (
    SELECT 
        user_id,
        vote_count,
        NTILE(10) OVER (ORDER BY vote_count DESC) AS user_tier
    FROM UserVoteCounts
)
SELECT 
    CASE 
        WHEN user_tier = 1 THEN '1. 상위 10% 유저'
        ELSE '2. 나머지 90% 유저' 
    END AS '유저 그룹',
    COUNT(user_id) AS '해당 그룹 유저 수',
    SUM(vote_count) AS '누적 득표수',
    ROUND(SUM(vote_count) / (SELECT SUM(vote_count) FROM UserVoteCounts) * 100, 2) AS '전체 투표 점유율(%)'
FROM RankedUsers
GROUP BY 1
ORDER BY 1;

SELECT 
    CASE 
        WHEN uqr.received_votes IS NULL THEN '1. 0표 유저 (유령/이탈 의심군)'
        ELSE '2. 1표 이상 수신 유저 (활성 유저군)'
    END AS '유저 그룹',
    COUNT(u.id) AS '유저 수',
    
    -- 친구 목록이 비어있는([] 또는 NULL) 유저의 비율
    ROUND(SUM(CASE WHEN u.friend_id_list = '[]' OR u.friend_id_list IS NULL THEN 1 ELSE 0 END) / COUNT(u.id) * 100, 2) AS '친구가 0명인 비율(%)',
    
    -- 푸시 알림을 켜둔 유저의 비율
    ROUND(AVG(u.is_push_on) * 100, 2) AS '푸시 알림 켜짐(%)',
    
    -- 평균적으로 보유하고 있는 포인트 (가입 기본금 그대로인지 확인)
    ROUND(AVG(u.point), 0) AS '평균 잔여 포인트'

FROM accounts_user u
LEFT JOIN (
    SELECT chosen_user_id, COUNT(id) AS received_votes
    FROM accounts_userquestionrecord
    GROUP BY chosen_user_id
) uqr ON u.id = uqr.chosen_user_id
WHERE u.is_staff = 0 AND u.is_superuser = 0
GROUP BY 1
ORDER BY 1;

SELECT 
    DATE(u.created_at) AS '가입 일자',
    COUNT(DISTINCT u.id) AS '당일 가입자 수',
    
    -- D+1 (가입 다음 날 활동한 유저 비율)
    ROUND(COUNT(DISTINCT CASE WHEN DATEDIFF(DATE(p.created_at), DATE(u.created_at)) = 1 THEN u.id END) / COUNT(DISTINCT u.id) * 100, 2) AS 'D+1 리텐션(%)',
    
    -- D+3 (가입 3일 뒤 활동한 유저 비율)
    ROUND(COUNT(DISTINCT CASE WHEN DATEDIFF(DATE(p.created_at), DATE(u.created_at)) = 3 THEN u.id END) / COUNT(DISTINCT u.id) * 100, 2) AS 'D+3 리텐션(%)',
    
    -- D+7 (가입 7일 뒤 활동한 유저 비율)
    ROUND(COUNT(DISTINCT CASE WHEN DATEDIFF(DATE(p.created_at), DATE(u.created_at)) = 7 THEN u.id END) / COUNT(DISTINCT u.id) * 100, 2) AS 'D+7 리텐션(%)'

FROM accounts_user u
LEFT JOIN accounts_pointhistory p ON u.id = p.user_id
WHERE u.is_staff = 0 AND u.is_superuser = 0
  AND u.created_at >= '2023-04-01' -- 특정 시점 이후 가입자만 필터링 (데이터 양에 따라 조절)
GROUP BY DATE(u.created_at)
ORDER BY DATE(u.created_at) DESC
LIMIT 15;

SELECT 
    DATE(u.created_at) AS '가입 일자',
    COUNT(DISTINCT u.id) AS '당일 가입자 수',
    
    ROUND(COUNT(DISTINCT CASE WHEN DATEDIFF(DATE(p.created_at), DATE(u.created_at)) = 1 THEN u.id END) / COUNT(DISTINCT u.id) * 100, 2) AS 'D+1 리텐션(%)',
    ROUND(COUNT(DISTINCT CASE WHEN DATEDIFF(DATE(p.created_at), DATE(u.created_at)) = 3 THEN u.id END) / COUNT(DISTINCT u.id) * 100, 2) AS 'D+3 리텐션(%)',
    ROUND(COUNT(DISTINCT CASE WHEN DATEDIFF(DATE(p.created_at), DATE(u.created_at)) = 7 THEN u.id END) / COUNT(DISTINCT u.id) * 100, 2) AS 'D+7 리텐션(%)'

FROM accounts_user u
LEFT JOIN accounts_pointhistory p ON u.id = p.user_id
WHERE u.is_staff = 0 AND u.is_superuser = 0
GROUP BY DATE(u.created_at)
HAVING COUNT(DISTINCT u.id) > 1000  -- 하루 가입자가 1,000명 이상인 '진짜 활성기'만 추출
ORDER BY 2 DESC                     -- 당일 가입자가 가장 많았던 날짜 순으로 정렬
LIMIT 15;

SELECT 
    CASE 
        WHEN uqr.received_votes IS NULL THEN '1. 투표 0표 수신 유저'
        ELSE '2. 투표 1표 이상 수신 유저'
    END AS '유저 그룹',
    COUNT(DISTINCT u.id) AS '총 가입자 수',
    ROUND(COUNT(DISTINCT CASE WHEN DATEDIFF(DATE(p.created_at), DATE(u.created_at)) = 1 THEN u.id END) / COUNT(DISTINCT u.id) * 100, 2) AS 'D+1 리텐션(%)',
    ROUND(COUNT(DISTINCT CASE WHEN DATEDIFF(DATE(p.created_at), DATE(u.created_at)) = 3 THEN u.id END) / COUNT(DISTINCT u.id) * 100, 2) AS 'D+3 리텐션(%)',
    ROUND(COUNT(DISTINCT CASE WHEN DATEDIFF(DATE(p.created_at), DATE(u.created_at)) = 7 THEN u.id END) / COUNT(DISTINCT u.id) * 100, 2) AS 'D+7 리텐션(%)'
FROM accounts_user u
LEFT JOIN (
    SELECT chosen_user_id, COUNT(id) AS received_votes
    FROM accounts_userquestionrecord
    GROUP BY chosen_user_id
) uqr ON u.id = uqr.chosen_user_id
LEFT JOIN accounts_pointhistory p ON u.id = p.user_id
WHERE u.is_staff = 0 AND u.is_superuser = 0
  AND u.created_at BETWEEN '2023-05-01' AND '2023-05-31' -- 트래픽 폭발 시기
GROUP BY 1
ORDER BY 1;

SELECT 
    q.question_text AS '질문 내용',
    COUNT(DISTINCT p.user_id) AS '포인트를 쓴 유저 수',
    SUM(ABS(p.delta_point)) AS '총 소모 포인트 (매출 기여도)',
    ROUND(SUM(ABS(p.delta_point)) / COUNT(DISTINCT p.user_id), 0) AS '1인당 평균 소모 포인트'
FROM accounts_pointhistory p
JOIN accounts_userquestionrecord uqr ON p.user_question_record_id = uqr.id
JOIN polls_question q ON uqr.question_id = q.id
WHERE p.delta_point < 0
GROUP BY q.question_text
ORDER BY SUM(ABS(p.delta_point)) DESC
LIMIT 20;


SELECT * FROM accounts_user LIMIT 5;


SELECT 
    CASE 
        WHEN u.gender = 'M' THEN '남성'
        WHEN u.gender = 'F' THEN '여성'
        ELSE '미상(NULL)' 
    END AS '성별',
    COUNT(DISTINCT p.user_id) AS '포인트 소모 유저 수',
    SUM(ABS(p.delta_point)) AS '총 소모 포인트 (매출 볼륨)',
    ROUND(SUM(ABS(p.delta_point)) / COUNT(DISTINCT p.user_id), 0) AS '1인당 평균 소모 포인트 (ARPU)'
FROM accounts_pointhistory p
JOIN accounts_user u ON p.user_id = u.id
WHERE p.delta_point < 0 
  AND u.is_staff = 0       -- 관리자 계정 제외
  AND u.is_superuser = 0   -- 최고 관리자 계정 제외
GROUP BY u.gender
ORDER BY SUM(ABS(p.delta_point)) DESC;

SELECT 
    CASE 
        WHEN q.question_text LIKE '%이상형%' OR q.question_text LIKE '%연애%' OR q.question_text LIKE '%관심%' OR q.question_text LIKE '%사귀고%' THEN '1. 로맨스/호감'
        WHEN q.question_text LIKE '%친해지고%' OR q.question_text LIKE '%짱친%' OR q.question_text LIKE '%친구%' THEN '2. 우정/관계 형성'
        WHEN q.question_text LIKE '%잘생긴%' OR q.question_text LIKE '%예쁜%' OR q.question_text LIKE '%매력%' THEN '3. 외모/매력 칭찬'
        ELSE '4. 기타/일반'
    END AS '문구 테마',
    COUNT(DISTINCT p.user_id) AS '지갑을 연 유저 수',
    SUM(ABS(p.delta_point)) AS '총 소모 포인트 (매출 볼륨)',
    ROUND(SUM(ABS(p.delta_point)) / COUNT(DISTINCT p.user_id), 0) AS '1인당 평균 결제액'
FROM accounts_pointhistory p
JOIN accounts_userquestionrecord uqr ON p.user_question_record_id = uqr.id
JOIN polls_question q ON uqr.question_id = q.id
WHERE p.delta_point < 0
GROUP BY '문구 테마'
ORDER BY SUM(ABS(p.delta_point)) DESC;

-- 전체 유저 신고 건수
SELECT COUNT(id) AS total_user_reports 
FROM accounts_timelinereport;

-- 전체 질문 신고 건수
SELECT COUNT(id) AS total_question_reports 
FROM polls_questionreport;

-- 전체 유저 차단 건수
SELECT COUNT(id) AS total_blocks 
FROM accounts_blockrecord;

-- 유저 신고 사유별 건수 및 비율
SELECT 
    reason, 
    COUNT(id) AS report_count
FROM accounts_timelinereport
GROUP BY reason
ORDER BY report_count DESC;

-- 유저 차단 사유별 건수 및 비율
SELECT 
    reason, 
    COUNT(id) AS block_count
FROM accounts_blockrecord
GROUP BY reason
ORDER BY block_count DESC;

-- 질문 신고 사유별 건수
SELECT 
    reason, 
    COUNT(id) AS question_report_count
FROM polls_questionreport
GROUP BY reason
ORDER BY question_report_count DESC;

-- 신고를 가장 많이 당한 상위 10명의 유저 추출
SELECT 
    reported_user_id, 
    COUNT(id) AS received_report_count
FROM accounts_timelinereport
GROUP BY reported_user_id
HAVING COUNT(id) >= 1
ORDER BY received_report_count DESC
LIMIT 10;

-- 차단 기능 사용 규모 확인
SELECT COUNT(id) AS total_blocks 
FROM accounts_blockrecord;


SELECT 
    total.user_cnt AS '전체 유저 수',
    report.reported_cnt AS '신고 당한 유저 수',
    ROUND((report.reported_cnt / total.user_cnt) * 100, 2) AS '신고 당한 유저 비율(%)',
    block.blocked_cnt AS '차단 당한 유저 수',
    ROUND((block.blocked_cnt / total.user_cnt) * 100, 2) AS '차단 당한 유저 비율(%)'
FROM 
    (SELECT COUNT(id) AS user_cnt FROM accounts_user) AS total,
    (SELECT COUNT(DISTINCT reported_user_id) AS reported_cnt FROM accounts_timelinereport) AS report,
    (SELECT COUNT(DISTINCT block_user_id) AS blocked_cnt FROM accounts_blockrecord) AS block;
    
SELECT * 
FROM accounts_pointhistory 
LIMIT 5;

SELECT 
    user_id,
    DATE(created_at) AS spend_date,
    COUNT(id) AS spend_count,       -- 포인트 사용 횟수
    SUM(ABS(delta_point)) AS total_spent -- 총 사용 포인트 (음수를 양수로 변환하여 합산)
FROM accounts_pointhistory
WHERE delta_point < 0  -- 포인트 소모 내역만 필터링
GROUP BY user_id, spend_date
HAVING spend_count >= 3           -- 하루에 3번 이상 포인트 사용
   AND total_spent >= 1500        -- 하루에 1500포인트 이상 소모 (초성 힌트를 끝까지 열어본 유저)
ORDER BY total_spent DESC, spend_count DESC;

-- 패닉 소비를 유발한 '문제의 투표(질문)' TOP 10 추출
WITH PanicSpenders AS (
    SELECT 
        user_id,
        user_question_record_id,
        SUM(ABS(delta_point)) AS total_spent
    FROM accounts_pointhistory
    WHERE delta_point < 0
    GROUP BY user_id, user_question_record_id
    HAVING total_spent >= 1700 -- 한 투표에 1500P 이상(초성 3개 다 열람) 소모
)
SELECT 
    q.question_text AS '질문 내용',
    COUNT(p.user_id) AS '패닉 소비 유발 횟수'
FROM PanicSpenders p
JOIN accounts_userquestionrecord uqr ON p.user_question_record_id = uqr.id
JOIN polls_question q ON uqr.question_id = q.id
GROUP BY q.question_text
ORDER BY COUNT(p.user_id) DESC
LIMIT 10;

# 헤비 유저들은 어떤 질문을 받고으면 결제를 많이 할까?
WITH UserSpend AS (
    -- 1. 유저별 총 소모 포인트 계산
    SELECT 
        user_id,
        SUM(ABS(delta_point)) AS total_spent
    FROM accounts_pointhistory
    WHERE delta_point < 0
    GROUP BY user_id
),
RankedSpend AS (
    -- 2. 결제액 기준 100분위(백분율) 랭킹 부여
    SELECT 
        user_id,
        total_spent,
        NTILE(100) OVER (ORDER BY total_spent DESC) AS percentile_rank
    FROM UserSpend
),
VIPUsers AS (
    -- 3. 상위 1% VIP 유저만 추출
    SELECT user_id
    FROM RankedSpend
    WHERE percentile_rank = 1
)
-- 4. VIP들이 가장 많은 포인트를 소모한 질문 텍스트 추출
SELECT 
    q.question_text AS 'VIP의 지갑을 연 질문 (트리거)',
    COUNT(DISTINCT p.user_id) AS '결제한 VIP 유저 수',
    SUM(ABS(p.delta_point)) AS 'VIP 총 소모 포인트',
    ROUND(SUM(ABS(p.delta_point)) / COUNT(DISTINCT p.user_id), 0) AS 'VIP 1인당 평균 결제액'
FROM accounts_pointhistory p
JOIN VIPUsers v ON p.user_id = v.user_id
JOIN accounts_userquestionrecord uqr ON p.user_question_record_id = uqr.id
JOIN polls_question q ON uqr.question_id = q.id
WHERE p.delta_point < 0
  AND q.question_text != 'vote'
GROUP BY 1
ORDER BY 3 DESC
LIMIT 20;

# 어떤 기능에 포인트를 쓰고 있을까?
WITH UserSpend AS (
    -- 1. 유저별 총 소모 포인트 계산
    SELECT 
        user_id,
        SUM(ABS(delta_point)) AS total_spent
    FROM accounts_pointhistory
    WHERE delta_point < 0
    GROUP BY user_id
),
RankedSpend AS (
    -- 2. 결제액 기준 10분위(10%) 랭킹 부여
    SELECT 
        user_id,
        total_spent,
        NTILE(10) OVER (ORDER BY total_spent DESC) AS user_tier
    FROM UserSpend
),
Top10Users AS (
    -- 3. 상위 10% 유저만 추출
    SELECT user_id
    FROM RankedSpend
    WHERE user_tier = 1
)
-- 4. 차감된 액수(상품 단가)별 결제 볼륨 분석
SELECT 
    p.delta_point AS '상품 단가 (차감액)',
    COUNT(p.id) AS '결제 횟수',
    SUM(ABS(p.delta_point)) AS '해당 상품 총 매출 볼륨',
    ROUND(SUM(ABS(p.delta_point)) / (
        SELECT SUM(ABS(p2.delta_point)) 
        FROM accounts_pointhistory p2 
        JOIN Top10Users t2 ON p2.user_id = t2.user_id 
        WHERE p2.delta_point < 0
    ) * 100, 2) AS '전체 소모 비중(%)'
FROM accounts_pointhistory p
JOIN Top10Users t ON p.user_id = t.user_id
WHERE p.delta_point < 0
GROUP BY p.delta_point
ORDER BY 3 DESC;

# 차감된 포인트 기준 결제 패턴 확인
SELECT 
    delta_point AS '차감 포인트 (단가)',
    COUNT(id) AS '총 결제 횟수',
    
    -- 특정 투표(받은 질문)와 연결된 결제인지 확인
    SUM(CASE WHEN user_question_record_id IS NOT NULL THEN 1 ELSE 0 END) AS '특정 질문에 사용됨 (힌트 열람)',
    
    -- 질문과 무관하게 허공에 사용된 결제인지 확인
    SUM(CASE WHEN user_question_record_id IS NULL THEN 1 ELSE 0 END) AS '질문과 무관함 (셔플/투표권 등)'

FROM accounts_pointhistory
WHERE delta_point < 0
GROUP BY delta_point
ORDER BY COUNT(id) DESC;

# 차감 금액별 행동
SELECT 
    productId AS '결제 상품 (Product ID)',
    COUNT(id) AS '실제 결제 건수',
    
    -- 전체 결제에서 이 상품이 차지하는 비중
    ROUND(COUNT(id) / (SELECT COUNT(*) FROM accounts_paymenthistory) * 100, 2) AS '결제 건수 비중(%)',
    
    -- iOS와 안드로이드 비율 확인
    SUM(CASE WHEN phone_type = 'ios' THEN 1 ELSE 0 END) AS 'iOS 결제 건수',
    SUM(CASE WHEN phone_type = 'android' THEN 1 ELSE 0 END) AS 'Android 결제 건수'
FROM accounts_paymenthistory
GROUP BY productId
ORDER BY COUNT(id) DESC;

# 가격표 확인 후 예상 금액
WITH PaymentData AS (
    SELECT 
        user_id,
        productId,
        CASE 
            WHEN productId LIKE '%200%' THEN 900
            WHEN productId LIKE '%777%' THEN 1900
            WHEN productId LIKE '%1000%' THEN 2900
            WHEN productId LIKE '%4000%' THEN 9900
            ELSE 0 
        END AS price,
        CASE 
            WHEN productId LIKE '%200%' THEN '200 하트 (900원)'
            WHEN productId LIKE '%777%' THEN '777 하트 (1,900원)'
            WHEN productId LIKE '%1000%' THEN '1000 하트 (2,900원)'
            WHEN productId LIKE '%4000%' THEN '4000 하트 (9,900원)'
            ELSE '기타/알 수 없음'
        END AS product_name
    FROM accounts_paymenthistory
)
SELECT 
    product_name AS '상품명',
    COUNT(*) AS '결제 건수',
    SUM(price) AS '예상 총 매출액(원)',
    ROUND(COUNT(*) / (SELECT COUNT(*) FROM PaymentData WHERE price > 0) * 100, 2) AS '결제 건수 비중(%)',
    ROUND(SUM(price) / (SELECT SUM(price) FROM PaymentData) * 100, 2) AS '매출 기여도 비중(%)'
FROM PaymentData
WHERE price > 0
GROUP BY product_name
ORDER BY SUM(price) DESC;

# ARPPU (결제 유저당 객단가) 계산
WITH PaymentData AS (
    SELECT 
        user_id,
        CASE 
            WHEN productId LIKE '%200%' THEN 900
            WHEN productId LIKE '%777%' THEN 1900
            WHEN productId LIKE '%1000%' THEN 2900
            WHEN productId LIKE '%4000%' THEN 9900
            ELSE 0 
        END AS price
    FROM accounts_paymenthistory
)
SELECT 
    SUM(price) AS '총 누적 매출액(원)',
    COUNT(DISTINCT user_id) AS '총 결제 유저 수(PU)',
    ROUND(SUM(price) / COUNT(DISTINCT user_id), 0) AS 'ARPPU (결제 유저당 평균 누적 결제액)',
    
    -- 참고용: 전체 가입자 대비 결제 유저 비율 (전환율)
    ROUND(COUNT(DISTINCT user_id) / (SELECT COUNT(id) FROM accounts_user WHERE is_staff = 0 AND is_superuser = 0) * 100, 2) AS '전체 유저 대비 결제 전환율(%)'
FROM PaymentData
WHERE price > 0;

# 전체 유저 대비 결제 전환율
SELECT 
    COUNT(DISTINCT u.id) AS '전체 일반 가입자 수',
    COUNT(DISTINCT p.user_id) AS '누적 결제 유저 수 (PU)',
    ROUND(COUNT(DISTINCT p.user_id) / COUNT(DISTINCT u.id) * 100, 2) AS '최종 결제 전환율(%)'
FROM accounts_user u
LEFT JOIN accounts_paymenthistory p ON u.id = p.user_id
WHERE u.is_staff = 0 AND u.is_superuser = 0;

#골든 타임 분석
WITH FirstPayment AS (
    -- 유저별 최초 결제 시점 추출
    SELECT 
        user_id,
        MIN(created_at) AS first_payment_time
    FROM accounts_paymenthistory
    GROUP BY user_id
)
SELECT 
    CASE 
        WHEN TIMESTAMPDIFF(HOUR, u.created_at, f.first_payment_time) < 24 THEN '1. 가입 후 24시간 이내 (즉시 결제)'
        WHEN TIMESTAMPDIFF(HOUR, u.created_at, f.first_payment_time) BETWEEN 24 AND 168 THEN '2. 가입 후 1주일 이내'
        WHEN TIMESTAMPDIFF(HOUR, u.created_at, f.first_payment_time) BETWEEN 168 AND 720 THEN '3. 가입 후 1달 이내'
        ELSE '4. 1달 이후 (장기 유저 전환)'
    END AS '첫 결제 소요 시간',
    COUNT(f.user_id) AS '결제 유저 수',
    ROUND(COUNT(f.user_id) / (SELECT COUNT(DISTINCT user_id) FROM accounts_paymenthistory) * 100, 2) AS '비율(%)'
FROM accounts_user u
JOIN FirstPayment f ON u.id = f.user_id
WHERE u.is_staff = 0 AND u.is_superuser = 0
GROUP BY 1
ORDER BY 1;

# 결제 트리거 분석
SELECT 
    pq.question_text AS '결제 유발 질문',
    COUNT(p.id) AS '힌트 열람(결제) 횟수',
    SUM(ABS(p.delta_point)) AS '총 소모 포인트',
    
    -- 전체 결제에서 이 질문이 차지하는 비중 (%)
    ROUND(COUNT(p.id) / (SELECT COUNT(id) FROM accounts_pointhistory WHERE delta_point < 0 AND user_question_record_id IS NOT NULL) * 100, 2) AS '매출 기여도(%)'
    
FROM accounts_pointhistory p
-- 1. 포인트 소모 기록과 유저가 받은 투표 기록 매핑
JOIN accounts_userquestionrecord uqr ON p.user_question_record_id = uqr.id
-- 2. 해당 투표의 실제 질문 텍스트 매핑
JOIN polls_question pq ON uqr.question_id = pq.id
-- 3. 조건: 포인트가 차감된(결제된) 기록만 필터링
WHERE p.delta_point < 0 
GROUP BY pq.id, pq.question_text
ORDER BY COUNT(p.id) DESC
LIMIT 20;

WITH FirstPayment AS (
    -- 1. 유저별 최초 결제 시점 추출 (기준점)
    SELECT 
        user_id, 
        MIN(created_at) AS first_pay_time
    FROM accounts_paymenthistory
    GROUP BY user_id
)
SELECT 
    COUNT(DISTINCT f.user_id) AS '총 결제 유저 수',
    
    -- 결제 다음 날(D+1)에 포인트 변동(활동)이 있는 유저 비율
    ROUND(COUNT(DISTINCT CASE WHEN DATEDIFF(DATE(p.created_at), DATE(f.first_pay_time)) = 1 THEN f.user_id END) / COUNT(DISTINCT f.user_id) * 100, 2) AS '결제 후 D+1 생존율(%)',
    
    -- 결제 후 3일 차(D+3)에 활동이 있는 유저 비율
    ROUND(COUNT(DISTINCT CASE WHEN DATEDIFF(DATE(p.created_at), DATE(f.first_pay_time)) = 3 THEN f.user_id END) / COUNT(DISTINCT f.user_id) * 100, 2) AS '결제 후 D+3 생존율(%)',
    
    -- 결제 후 7일 차(D+7)에 활동이 있는 유저 비율
    ROUND(COUNT(DISTINCT CASE WHEN DATEDIFF(DATE(p.created_at), DATE(f.first_pay_time)) = 7 THEN f.user_id END) / COUNT(DISTINCT f.user_id) * 100, 2) AS '결제 후 D+7 생존율(%)'
    
FROM FirstPayment f
LEFT JOIN accounts_pointhistory p ON f.user_id = p.user_id;

WITH FirstPayment AS (
    -- 1. 유저별 최초 결제 시점 추출 (기준일 지정)
    SELECT 
        user_id, 
        DATE(MIN(created_at)) AS first_pay_date
    FROM accounts_paymenthistory
    GROUP BY user_id
),
UserActivity AS (
    -- 2. 핵클 이벤트 로그를 통해 유저가 실제로 앱에서 활동한 날짜 추출
    SELECT DISTINCT
        hp.user_id,
        DATE(he.event_datetime) AS activity_date
    FROM hackle_properties hp
    JOIN hackle_events he ON hp.session_id = he.session_id
)
SELECT 
    COUNT(DISTINCT f.user_id) AS '총 결제 유저 수',
    
    -- 결제 다음 날(D+1) 앱 내 활동 이력이 있는 유저 비율
    ROUND(COUNT(DISTINCT CASE WHEN DATEDIFF(a.activity_date, f.first_pay_date) = 1 THEN f.user_id END) / COUNT(DISTINCT f.user_id) * 100, 2) AS '결제 후 D+1 생존율(%)',
    
    -- 결제 후 3일 차(D+3) 활동 이력
    ROUND(COUNT(DISTINCT CASE WHEN DATEDIFF(a.activity_date, f.first_pay_date) = 3 THEN f.user_id END) / COUNT(DISTINCT f.user_id) * 100, 2) AS '결제 후 D+3 생존율(%)',
    
    -- 결제 후 7일 차(D+7) 활동 이력
    ROUND(COUNT(DISTINCT CASE WHEN DATEDIFF(a.activity_date, f.first_pay_date) = 7 THEN f.user_id END) / COUNT(DISTINCT f.user_id) * 100, 2) AS '결제 후 D+7 생존율(%)'
    
FROM FirstPayment f
LEFT JOIN UserActivity a ON f.user_id = a.user_id;

WITH UserEvents AS (
    -- 유저별로 앱에서 액션을 일으킨 날짜(이벤트 로그)를 추출 (중복 제거)
    SELECT DISTINCT
        hp.user_id,
        DATE(he.event_datetime) AS activity_date
    FROM hackle_properties hp
    JOIN hackle_events he ON hp.session_id = he.session_id
)
SELECT 
    COUNT(DISTINCT u.id) AS '총 누적 가입자 수',
    
    -- 가입 다음 날(D+1) 앱 내 활동 이력이 있는 유저 비율 (진짜 리텐션)
    ROUND(COUNT(DISTINCT CASE WHEN DATEDIFF(e.activity_date, DATE(u.created_at)) = 1 THEN u.id END) / COUNT(DISTINCT u.id) * 100, 2) AS '진짜 평균 D+1 접속 리텐션(%)',
    
    -- 가입 후 3일 차(D+3) 진짜 리텐션
    ROUND(COUNT(DISTINCT CASE WHEN DATEDIFF(e.activity_date, DATE(u.created_at)) = 3 THEN u.id END) / COUNT(DISTINCT u.id) * 100, 2) AS '진짜 평균 D+3 접속 리텐션(%)',
    
    -- 가입 후 7일 차(D+7) 진짜 리텐션
    ROUND(COUNT(DISTINCT CASE WHEN DATEDIFF(e.activity_date, DATE(u.created_at)) = 7 THEN u.id END) / COUNT(DISTINCT u.id) * 100, 2) AS '진짜 평균 D+7 접속 리텐션(%)'

FROM accounts_user u
LEFT JOIN UserEvents e ON u.id = e.user_id
WHERE u.is_staff = 0 AND u.is_superuser = 0;

SELECT 
    MIN(he.event_datetime) AS '핵클 로그 최초 수집일',
    MAX(he.event_datetime) AS '핵클 로그 최근 수집일',
    COUNT(DISTINCT hp.user_id) AS '핵클 로그에 기록된 총 유저 수',
    (SELECT COUNT(id) FROM accounts_user WHERE is_staff = 0 AND is_superuser = 0) AS '실제 총 가입자 수'
FROM hackle_events he
JOIN hackle_properties hp ON he.session_id = hp.session_id;

WITH FirstPayment AS (
    -- 유저별 최초 결제 시점 추출
    SELECT user_id, MIN(created_at) AS first_pay_time
    FROM accounts_paymenthistory
    GROUP BY user_id
),
VotesBeforePayment AS (
    -- 첫 결제 '이전'에 받은 투표 수만 카운트
    SELECT 
        uqr.chosen_user_id, 
        COUNT(uqr.id) AS received_votes
    FROM accounts_userquestionrecord uqr
    JOIN FirstPayment fp ON uqr.chosen_user_id = fp.user_id
    WHERE uqr.created_at < fp.first_pay_time 
    GROUP BY uqr.chosen_user_id
)
SELECT 
    CASE 
        WHEN v.received_votes = 1 THEN '1. 단 1표 수신 후 결제'
        WHEN v.received_votes BETWEEN 2 AND 3 THEN '2. 2~3표 수신 후 결제'
        WHEN v.received_votes BETWEEN 4 AND 6 THEN '3. 4~6표 수신 후 결제'
        WHEN v.received_votes >= 7 THEN '4. 7표 이상 수신 후 결제'
        ELSE '5. 0표 수신 (본인 발송을 위한 과금 등)'
    END AS '첫 결제 직전 누적 수신 투표 수',
    COUNT(f.user_id) AS '해당 유저 수',
    ROUND(COUNT(f.user_id) / (SELECT COUNT(*) FROM FirstPayment) * 100, 2) AS '비율(%)'
FROM FirstPayment f
LEFT JOIN VotesBeforePayment v ON f.user_id = v.chosen_user_id
GROUP BY 1
ORDER BY 1;

WITH CombinedActivity AS (
    -- 1. 포인트 변동이 있었던 날짜 (가장 확실한 활동 증명)
    SELECT user_id, DATE(created_at) AS activity_date 
    FROM accounts_pointhistory
    
    UNION
    
    -- 2. 결제가 있었던 날짜
    SELECT user_id, DATE(created_at) AS activity_date 
    FROM accounts_paymenthistory
    
    UNION
    
    -- 3. 누군가에게 투표를 보낸 날짜 (투표 발송자 ID 컬럼이 있다고 가정)
    -- * 만약 sender_id 컬럼이 없다면 이 부분은 제외
    SELECT sender_user_id AS user_id, DATE(created_at) AS activity_date 
    FROM accounts_userquestionrecord
)
SELECT 
    user_id,
    activity_date
FROM CombinedActivity
GROUP BY user_id, activity_date;

WITH FirstPayment AS (
    SELECT user_id, MIN(created_at) AS first_pay_time
    FROM accounts_paymenthistory
    GROUP BY user_id
),
VotesBeforePayment AS (
    SELECT uqr.chosen_user_id, COUNT(uqr.id) AS received_votes
    FROM accounts_userquestionrecord uqr
    JOIN FirstPayment fp ON uqr.chosen_user_id = fp.user_id
    WHERE uqr.created_at < fp.first_pay_time
    GROUP BY uqr.chosen_user_id
),
ZeroVotePayers AS (
    SELECT f.user_id, f.first_pay_time
    FROM FirstPayment f
    LEFT JOIN VotesBeforePayment v ON f.user_id = v.chosen_user_id
    WHERE v.received_votes IS NULL OR v.received_votes = 0
),
FirstExpenditure AS (
    SELECT 
        p.user_id, 
        p.user_question_record_id,
        ROW_NUMBER() OVER(PARTITION BY p.user_id ORDER BY p.created_at ASC) as rn
    FROM accounts_pointhistory p
    JOIN ZeroVotePayers z ON p.user_id = z.user_id
    WHERE p.delta_point < 0 
      AND p.created_at >= z.first_pay_time 
)
SELECT 
    CASE 
        WHEN user_question_record_id IS NULL THEN '1. 투표와 무관한 지출 (프로필 방문자 확인, 기능 해제 등)'
        ELSE '2. 투표 발송 관련 지출 (선택지 셔플, 특정인 지정 투표 등)'
    END AS '첫 포인트 사용처 분류',
    COUNT(user_id) AS '해당 유저 수',
    ROUND(COUNT(user_id) / (SELECT COUNT(*) FROM ZeroVotePayers) * 100, 2) AS '비율(%)'
FROM FirstExpenditure
WHERE rn = 1
GROUP BY 1
ORDER BY 1;

WITH CombinedActivity AS (
    -- 1. 포인트 변동이 있었던 날짜 (가장 확실한 활동 증명)
    SELECT user_id, DATE(created_at) AS activity_date 
    FROM accounts_pointhistory
    
    UNION
    
    -- 2. 결제가 있었던 날짜
    SELECT user_id, DATE(created_at) AS activity_date 
    FROM accounts_paymenthistory
)
SELECT 
    user_id,
    activity_date
FROM CombinedActivity
GROUP BY user_id, activity_date;