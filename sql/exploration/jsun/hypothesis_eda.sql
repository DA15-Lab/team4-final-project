-- 주제: 사용자 행동과 리텐션이 결제 전환 및 반복 구매에 미치는 영향 분석
-- 핵심 질문: 어떤 사용자 행동이 서비스 잔존을 높이고, 결제 및 반복 구매로 이어지는가?

-- 가설 1. 친구 관계가 활발할수록 리텐션이 높다.
WITH session_user AS (
    SELECT DISTINCT
        session_id,
        user_id
    FROM final.hackle_properties
    WHERE user_id REGEXP '^[0-9]+$'
),

activity AS (
    SELECT DISTINCT
        CAST(su.user_id AS UNSIGNED) AS user_id,
        DATE(he.event_datetime) AS activity_date
    FROM final.hackle_events he
    JOIN session_user su
        ON he.session_id = su.session_id
),

first_activity AS (
    SELECT
        user_id,
        MIN(activity_date) AS first_date
    FROM activity
    GROUP BY user_id
),

retention AS (
    SELECT
        f.user_id,
        f.first_date,
        MAX(
            CASE
                WHEN DATEDIFF(a.activity_date, f.first_date) = 7 THEN 1
                ELSE 0
            END
        ) AS d7_retention
    FROM first_activity f
    LEFT JOIN activity a
        ON f.user_id = a.user_id
    WHERE f.first_date <= '2023-08-03'
    GROUP BY f.user_id, f.first_date
),

friend_activity AS (
    SELECT
        send_user_id AS user_id,
        COUNT(*) AS sent_request_count
    FROM final.accounts_friendrequest
    GROUP BY send_user_id
)

SELECT
    CASE
        WHEN COALESCE(f.sent_request_count, 0) = 0 THEN '0'
        WHEN f.sent_request_count BETWEEN 1 AND 5 THEN '1-5'
        WHEN f.sent_request_count BETWEEN 6 AND 10 THEN '6-10'
        WHEN f.sent_request_count BETWEEN 11 AND 20 THEN '11-20'
        ELSE '21+'
    END AS friend_group,
    COUNT(*) AS users,
    ROUND(100.0 * AVG(r.d7_retention), 2) AS d7_retention_rate
FROM retention r
LEFT JOIN friend_activity f
    ON r.user_id = f.user_id
GROUP BY friend_group
ORDER BY MIN(COALESCE(f.sent_request_count, 0));
-- '0','6630','8.42'
-- '1-5','13949','9.05'
-- '6-10','21116','9.41'
-- '11-20','48272','9.93'
-- '21+','103468','11.02'

-- -- 가설 1 결과 요약 --
-- 친구 요청 횟수가 증가할수록 D7 리텐션이 점진적으로 증가하는 패턴이 확인됨.

-- 친구 요청 0회      : 8.42%
-- 친구 요청 1~5회    : 9.05%
-- 친구 요청 6~10회   : 9.41%
-- 친구 요청 11~20회  : 9.93%
-- 친구 요청 21회 이상: 11.02%

-- 친구 요청 활동이 가장 적은 그룹과 가장 많은 그룹 간
-- D7 리텐션은 약 2.6%p 차이가 나타남.

-- 따라서 "친구 관계가 활발할수록 리텐션이 높다"는 가설을
-- 1차 EDA 수준에서는 지지하는 방향의 패턴이 확인됨.

-- 단, 현재 friend_activity는 보낸 친구 요청 횟수를 기준으로 하므로
-- 실제 친구 수 또는 친구 관계 성립 여부와는 다름.
-- 이후 friendrequest.status를 활용해 수락된 친구 관계 기준으로
-- 재분석할 필요가 있음.

-- 또한 본 결과는 연관관계이며 인과관계로 해석할 수 없음.


-- 가설2. 투표를 많이 받을수록 결제 가능성이 높다.
WITH received_vote AS (
    SELECT
        chosen_user_id AS user_id,
        COUNT(*) AS received_vote_count
    FROM final.accounts_userquestionrecord
    WHERE chosen_user_id IS NOT NULL
    GROUP BY chosen_user_id
),

payer AS (
    SELECT DISTINCT
        user_id,
        1 AS is_payer
    FROM final.accounts_paymenthistory
)

SELECT
    CASE
        WHEN COALESCE(v.received_vote_count, 0) = 0 THEN '0'
        WHEN v.received_vote_count BETWEEN 1 AND 5 THEN '1-5'
        WHEN v.received_vote_count BETWEEN 6 AND 10 THEN '6-10'
        WHEN v.received_vote_count BETWEEN 11 AND 20 THEN '11-20'
        ELSE '21+'
    END AS received_vote_group,
    COUNT(*) AS users,
    SUM(CASE WHEN p.is_payer = 1 THEN 1 ELSE 0 END) AS paying_users,
    ROUND(
        100.0 * AVG(COALESCE(p.is_payer, 0)),
        2
    ) AS payer_rate
FROM final.accounts_user u
LEFT JOIN received_vote v
    ON u.id = v.user_id
LEFT JOIN payer p
    ON u.id = p.user_id
GROUP BY received_vote_group
ORDER BY MIN(COALESCE(v.received_vote_count, 0));
-- '0','661659','57979','8.76'
-- '1-5','5122','403','7.87'
-- '6-10','1664','129','7.75'
-- '11-20','1697','119','7.01'
-- '21+','6943','562','8.09'

-- -- 가설 2 결과 요약 --
-- 받은 투표 수가 증가할수록 결제율이 높아질 것이라는 가설을 확인함.

-- 받은 투표 0회      : 8.76%
-- 받은 투표 1~5회    : 7.87%
-- 받은 투표 6~10회   : 7.75%
-- 받은 투표 11~20회  : 7.01%
-- 받은 투표 21회 이상: 8.09%

-- 받은 투표 수가 증가할수록 결제율이 일관되게 증가하는 패턴은 확인되지 않음.
-- 오히려 일부 구간에서는 결제율이 낮아지는 경향이 나타남.

-- 따라서 "투표를 많이 받을수록 결제 가능성이 높다"는 가설은
-- 1차 EDA 수준에서는 지지되지 않음.

-- 다만 현재는 전체 기간의 받은 투표 수와 전체 기간의 결제 경험 여부를
-- 단순 비교한 결과이므로 시간 순서를 고려하지 못함.

-- 실제로는
-- '투표를 받은 이후 일정 기간 내 결제가 발생했는지'
-- 또는 '결제 직전 받은 투표 수가 증가했는지'
-- 를 확인하는 방식으로 재분석할 필요가 있음.
-- 투표를 받은 직후 결제 가능성이 높아지는가?도 좋아보임.


-- 가설 3. 포인트 소비가 많을수록 결제 가능성이 높다.
WITH point_usage AS (
    SELECT
        user_id,
        SUM(
            CASE
                WHEN delta_point < 0 THEN ABS(delta_point)
                ELSE 0
            END
        ) AS spent_point
    FROM final.accounts_pointhistory
    GROUP BY user_id
),

payer AS (
    SELECT DISTINCT
        user_id,
        1 AS is_payer
    FROM final.accounts_paymenthistory
)

SELECT
    CASE
        WHEN COALESCE(pt.spent_point, 0) = 0 THEN '0'
        WHEN pt.spent_point <= 100 THEN '1-100'
        WHEN pt.spent_point <= 500 THEN '101-500'
        WHEN pt.spent_point <= 1000 THEN '501-1000'
        ELSE '1001+'
    END AS spent_point_group,
    COUNT(*) AS users,
    ROUND(
        100.0 * AVG(COALESCE(p.is_payer, 0)),
        2
    ) AS payer_rate
FROM final.accounts_user u
LEFT JOIN point_usage pt
    ON u.id = pt.user_id
LEFT JOIN payer p
    ON u.id = p.user_id
GROUP BY spent_point_group
ORDER BY MIN(COALESCE(pt.spent_point, 0));
-- '1-100','27','0.00'
-- '101-500','212','1.89'
-- '501-1000','367','1.91'
-- '0','672476','8.74'
-- '1001+','4003','9.89'

-- -- 가설 3 결과 요약 --
-- 포인트 소비량이 많을수록 결제율이 높을 것이라는 가설을 확인함.

-- 포인트 소비 0       : 672,476명 / 결제율 8.74%
-- 포인트 소비 1~100   :      27명 / 결제율 0.00%
-- 포인트 소비 101~500 :     212명 / 결제율 1.89%
-- 포인트 소비 501~1000:     367명 / 결제율 1.91%
-- 포인트 소비 1001+   :   4,003명 / 결제율 9.89%

-- 포인트 소비량이 증가할수록 결제율이 일관되게 증가하는 패턴은 확인되지 않음.
-- 따라서 "포인트 소비가 많을수록 결제 가능성이 높다"는 가설은
-- 현재의 단순 누적 기준에서는 명확하게 지지되지 않음.

-- 다만 1001포인트 이상 소비한 사용자군에서는
-- 결제율이 9.89%로 가장 높게 나타남.
-- 따라서 일정 수준 이상의 높은 포인트 소비가
-- 결제 행동과 관련될 가능성은 추가 확인할 필요가 있음.

-- 또한 포인트 소비 0인 사용자가 전체 사용자 중 압도적으로 많고,
-- 해당 집단의 결제율도 8.74%로 높게 나타남.
-- 이에 따라 accounts_pointhistory가 모든 포인트 소비 행동을
-- 기록하는지 데이터 구조를 추가 확인할 필요가 있음.

-- 현재 분석은 전체 기간의 누적 포인트 소비량과
-- 전체 기간의 결제 경험 여부를 비교한 것이므로
-- 포인트 소비와 결제의 시간적 선후관계는 확인할 수 없음.

-- 추후에는 최초 결제 이전 포인트 소비량 또는
-- 포인트 잔액 감소 이후 일정 기간 내 결제 여부를 기준으로
-- 재분석할 필요가 있음.


-- 가설 4. 리텐션이 높은 사용자는 반복 구매 가능성이 높다.
WITH session_user AS (
    SELECT DISTINCT
        session_id,
        user_id
    FROM final.hackle_properties
    WHERE user_id REGEXP '^[0-9]+$'
),

activity AS (
    SELECT DISTINCT
        CAST(su.user_id AS UNSIGNED) AS user_id,
        DATE(he.event_datetime) AS activity_date
    FROM final.hackle_events he
    JOIN session_user su
        ON he.session_id = su.session_id
),

first_activity AS (
    SELECT
        user_id,
        MIN(activity_date) AS first_date
    FROM activity
    GROUP BY user_id
),

retention AS (
    SELECT
        f.user_id,
        MAX(
            CASE
                WHEN DATEDIFF(a.activity_date, f.first_date) = 7 THEN 1
                ELSE 0
            END
        ) AS d7_retention
    FROM first_activity f
    LEFT JOIN activity a
        ON f.user_id = a.user_id
    WHERE f.first_date <= '2023-08-03'
    GROUP BY f.user_id
),

payment_summary AS (
    SELECT
        user_id,
        COUNT(*) AS payment_count
    FROM final.accounts_paymenthistory
    GROUP BY user_id
)

SELECT
    CASE
        WHEN p.payment_count = 1 THEN '1회 결제자'
        WHEN p.payment_count >= 2 THEN '반복 결제자'
    END AS payment_group,
    COUNT(*) AS users,
    ROUND(100.0 * AVG(r.d7_retention), 2) AS d7_retention_rate
FROM payment_summary p
JOIN retention r
    ON p.user_id = r.user_id
GROUP BY payment_group;
-- '반복 결제자','6652','12.91'
-- '1회 결제자','15284','11.25'

-- -- 가설 4 결과 요약 --
-- 1회 결제자와 반복 결제자의 D7 리텐션을 비교함.

-- 1회 결제자   : 15,284명 / D7 11.25%
-- 반복 결제자 :  6,652명 / D7 12.91%

-- 반복 결제자의 D7 리텐션이 1회 결제자보다 약 1.66%p 높게 나타남.

-- 따라서 "리텐션이 높은 사용자는 반복 구매 가능성이 높다"는 가설은
-- 1차 EDA 수준에서는 지지되는 방향의 패턴이 확인됨.

-- 다만 현재 결과는 반복 구매 여부별 D7 리텐션 차이를 비교한 것으로,
-- 리텐션이 반복 구매를 유발한다고 인과적으로 해석할 수는 없음.

-- 또한 Hackle 로그 관측 기간이 2023-07-18 ~ 2023-08-10으로 제한되어 있어
-- 해당 기간에 관측 가능한 결제 사용자만 포함된 결과임.

-- 추후에는
-- 1) D1 / D3 / D7 전체 비교
-- 2) 활동일 수 / 세션 수 비교
-- 3) 최초 결제 이후 재방문 여부와 반복 구매 간 관계
-- 등을 추가로 확인할 필요가 있음.


-- 가설 5. 초기 활동량이 높은 사용자는 반복 구매자가 될 가능성이 높다.
WITH session_user AS (
    SELECT DISTINCT
        session_id,
        user_id
    FROM final.hackle_properties
    WHERE user_id REGEXP '^[0-9]+$'
),

user_event AS (
    SELECT
        CAST(su.user_id AS UNSIGNED) AS user_id,
        he.event_datetime,
        DATE(he.event_datetime) AS activity_date
    FROM final.hackle_events he
    JOIN session_user su
        ON he.session_id = su.session_id
),

first_activity AS (
    SELECT
        user_id,
        MIN(activity_date) AS first_date
    FROM user_event
    GROUP BY user_id
),

early_activity AS (
    SELECT
        e.user_id,
        COUNT(*) AS early_event_count,
        COUNT(DISTINCT e.activity_date) AS early_active_days
    FROM user_event e
    JOIN first_activity f
        ON e.user_id = f.user_id
    WHERE DATEDIFF(e.activity_date, f.first_date) BETWEEN 0 AND 2
    GROUP BY e.user_id
),

payment_summary AS (
    SELECT
        user_id,
        COUNT(*) AS payment_count
    FROM final.accounts_paymenthistory
    GROUP BY user_id
)

SELECT
    CASE
        WHEN ea.early_event_count <= 10 THEN 'low'
        WHEN ea.early_event_count <= 50 THEN 'medium'
        ELSE 'high'
    END AS early_activity_group,
    COUNT(*) AS users,
    ROUND(
        100.0 * AVG(
            CASE
                WHEN p.payment_count >= 2 THEN 1
                ELSE 0
            END
        ),
        2
    ) AS repeat_purchase_rate
FROM early_activity ea
LEFT JOIN payment_summary p
    ON ea.user_id = p.user_id
GROUP BY early_activity_group
ORDER BY MIN(ea.early_event_count);
-- 'low','79546','3.01'
-- 'medium','128332','3.40'
-- 'high','22975','5.48'

-- -- 가설 5 결과 요약 --
-- 최초 활동일 포함 3일간의 이벤트 수를 기준으로
-- 초기 활동량 그룹을 low / medium / high로 구분하여
-- 반복 구매율을 비교함.

-- low    : 79,546명  / 반복 구매율 3.01%
-- medium : 128,332명 / 반복 구매율 3.40%
-- high   : 22,975명  / 반복 구매율 5.48%

-- 초기 활동량이 높아질수록 반복 구매율이 증가하는 패턴이 확인됨.
-- 특히 high 그룹의 반복 구매율은 low 그룹보다 약 2.47%p 높음.

-- 따라서 "초기 활동량이 높은 사용자는 반복 구매자가 될 가능성이 높다"는
-- 가설은 1차 EDA 수준에서 지지되는 방향의 패턴이 확인됨.

-- 다만 현재 early_event_count 구간(low / medium / high)은
-- 임의 기준으로 나눈 것이므로,
-- 추후에는 분위수(예: 25%, 50%, 75%) 또는 실제 분포를 기준으로
-- 그룹을 재정의할 필요가 있음.

-- 또한 결제 데이터의 전체 기간이 Hackle 로그보다 길기 때문에,
-- 향후 분석에서는 초기 활동 이후의 반복 구매만 포함하도록
-- 시간적 선후관계를 명확히 정의할 필요가 있음.