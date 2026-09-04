-- =========================================
-- churn_overview.sql
-- 목적:
-- 1. 사용자 활동 및 리텐션 구조 파악
-- 2. 이탈/잔존 사용자 특성 탐색
-- 3. 결제 여부 및 반복 구매와 리텐션 관계 확인
-- 4. 이탈 방지 관련 세부 주제 후보 도출
-- =========================================

-- =========================================
-- A. 사용자 활동 기본 현황
-- =========================================

-- 1. 사용자별 활동일 수
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
)

SELECT
    user_id,
    COUNT(DISTINCT activity_date) AS active_days
FROM activity
GROUP BY user_id
ORDER BY active_days DESC;
-- 사용자의 최대 활동일 수: 24일

-- 2. 활동일 수 구간별 사용자 분포
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

user_activity AS (
    SELECT
        user_id,
        COUNT(DISTINCT activity_date) AS active_days
    FROM activity
    GROUP BY user_id
)

SELECT
    CASE
        WHEN active_days = 1 THEN '1일'
        WHEN active_days BETWEEN 2 AND 3 THEN '2~3일'
        WHEN active_days BETWEEN 4 AND 7 THEN '4~7일'
        WHEN active_days BETWEEN 8 AND 14 THEN '8~14일'
        ELSE '15일 이상'
    END AS active_day_group,
    COUNT(*) AS user_count
FROM user_activity
GROUP BY active_day_group
ORDER BY MIN(active_days);
-- '1일','106045'
-- '2~3일','80216'
-- '4~7일','31508'
-- '8~14일','9151'
-- '15일 이상','3933'

-- 3. 사용자별 최초 활동일 / 마지막 활동일
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
)

SELECT
    user_id,
    MIN(activity_date) AS first_activity_date,
    MAX(activity_date) AS last_activity_date,
    DATEDIFF(MAX(activity_date), MIN(activity_date)) AS activity_span_days,
    COUNT(DISTINCT activity_date) AS active_days
FROM activity
GROUP BY user_id
ORDER BY activity_span_days DESC;

-- ------
-- 요약 --
-- ------
-- Hackle 이벤트 로그 기준 사용자의 최대 활동일 수는 24일로 확인됨.
-- 이는 전체 이벤트 관측 기간(2023-07-18 ~ 2023-08-10)과 동일함.

-- 활동일 수 구간별 사용자 분포
-- 1일       : 106,045명
-- 2~3일     : 80,216명
-- 4~7일     : 31,508명
-- 8~14일    : 9,151명
-- 15일 이상 : 3,933명

-- 전체적으로 활동일 수가 짧은 사용자 비중이 매우 높게 나타남.
-- 특히 1일만 활동한 사용자가 가장 많으며,
-- 3일 이하 활동한 사용자가 전체 사용자 중 큰 비중을 차지함.

-- 반면 8일 이상 활동한 사용자는 상대적으로 적고,
-- 15일 이상 활동한 사용자는 3,933명으로 소수에 해당함.

-- 따라서 서비스 이용 패턴은
-- "초기 단기 이용 사용자 다수 + 장기간 지속 이용 사용자 소수"
-- 형태로 나타나는 것으로 볼 수 있음.

-- 사용자별 최초 활동일 / 마지막 활동일을 통해
-- activity_span_days와 active_days를 함께 확인할 수 있음.

-- activity_span_days:
-- 최초 활동일과 마지막 활동일 사이의 날짜 간격

-- active_days:
-- 실제로 활동한 날짜의 개수

-- 예를 들어 최초 활동일이 7/18, 마지막 활동일이 8/10이고
-- 매일 활동했다면 activity_span_days = 23,
-- active_days = 24로 나타날 수 있음.

-- 추후에는 active_days뿐 아니라
-- activity_span_days와 active_days의 차이를 활용해
-- "짧은 기간에 몰아서 사용한 사용자"와
-- "오랜 기간 간헐적으로 재방문한 사용자"를 구분해볼 수 있음


-- =========================================
-- B. D1 / D3 / D7 리텐션
-- =========================================

-- 4. 전체 D1/D3/D7 리텐션
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
                WHEN DATEDIFF(a.activity_date, f.first_date) = 1 THEN 1
                ELSE 0
            END
        ) AS d1_retention,

        MAX(
            CASE
                WHEN DATEDIFF(a.activity_date, f.first_date) = 3 THEN 1
                ELSE 0
            END
        ) AS d3_retention,

        MAX(
            CASE
                WHEN DATEDIFF(a.activity_date, f.first_date) = 7 THEN 1
                ELSE 0
            END
        ) AS d7_retention

    FROM first_activity f
    LEFT JOIN activity a
        ON f.user_id = a.user_id
    GROUP BY f.user_id, f.first_date
)

SELECT
    ROUND(
        100.0 * AVG(
            CASE
                WHEN first_date <= '2023-08-09' THEN d1_retention
            END
        ),
        2
    ) AS d1_retention_rate,

    ROUND(
        100.0 * AVG(
            CASE
                WHEN first_date <= '2023-08-07' THEN d3_retention
            END
        ),
        2
    ) AS d3_retention_rate,

    ROUND(
        100.0 * AVG(
            CASE
                WHEN first_date <= '2023-08-03' THEN d7_retention
            END
        ),
        2
    ) AS d7_retention_rate
FROM retention;
-- '16.27','11.85','10.34'

-- 5. 사용자별 D1/D3/D7 flag
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
)

SELECT
    f.user_id,
    f.first_date,

    MAX(
        CASE
            WHEN DATEDIFF(a.activity_date, f.first_date) = 1 THEN 1
            ELSE 0
        END
    ) AS d1_retention,

    MAX(
        CASE
            WHEN DATEDIFF(a.activity_date, f.first_date) = 3 THEN 1
            ELSE 0
        END
    ) AS d3_retention,

    MAX(
        CASE
            WHEN DATEDIFF(a.activity_date, f.first_date) = 7 THEN 1
            ELSE 0
        END
    ) AS d7_retention

FROM first_activity f
LEFT JOIN activity a
    ON f.user_id = a.user_id
GROUP BY f.user_id, f.first_date;

-- ------
-- 요약 --
-- ------
-- 전체 사용자 기준 단기 리텐션
-- D1 리텐션 : 16.27%
-- D3 리텐션 : 11.85%
-- D7 리텐션 : 10.34%

-- 각 리텐션은 관측 가능한 사용자만 포함하여 계산함.
-- D1 : first_date <= 2023-08-09
-- D3 : first_date <= 2023-08-07
-- D7 : first_date <= 2023-08-03

-- 따라서 이벤트 로그 종료일(2023-08-10)에 가까운 후반 코호트가
-- 관측 기간 부족으로 0으로 처리되는 문제를 방지함.

-- 전체적으로 최초 활동 이후 시간이 지날수록
-- 재방문율이 낮아지는 패턴이 확인됨.

-- D1 → D3 : 16.27% → 11.85%
-- D3 → D7 : 11.85% → 10.34%

-- 특히 최초 활동 다음 날 다시 방문한 사용자는 약 16% 수준으로,
-- 초기 이탈 비중이 큰 편으로 볼 수 있음.

-- 다만 D3와 D7의 차이는 약 1.51%p로,
-- D3까지 남아있는 사용자 중 일부는 이후에도 비교적 유지되는
-- 패턴이 있을 가능성이 있음.

-- 사용자별 D1 / D3 / D7 flag도 생성함.
-- 예:
-- d1_retention = 1 → 최초 활동일 +1일에 활동
-- d3_retention = 1 → 최초 활동일 +3일에 활동
-- d7_retention = 1 → 최초 활동일 +7일에 활동

-- 이 사용자 단위 flag는 이후
-- 친구 관계 / 투표 행동 / 초기 활동량 / 결제 여부 / 반복 구매 여부
-- 등의 변수와 JOIN하여 리텐션 차이를 비교하는 데 활용할 수 있음.


-- =========================================
-- C. 결제 여부 / 반복 구매와 리텐션
-- =========================================

-- 6. 비결제자 / 1회 결제자 / 반복 결제자 D7 비교
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
        WHEN p.payment_count IS NULL THEN '비결제자'
        WHEN p.payment_count = 1 THEN '1회 결제자'
        ELSE '반복 결제자'
    END AS payment_group,

    COUNT(*) AS users,

    ROUND(
        100.0 * AVG(r.d7_retention),
        2
    ) AS d7_retention_rate

FROM retention r
LEFT JOIN payment_summary p
    ON r.user_id = p.user_id
GROUP BY payment_group;
-- '비결제자','171499','10.16'
-- '1회 결제자','15284','11.25'
-- '반복 결제자','6652','12.91'

-- 7. 결제 그룹별 평균 활동일 수
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

user_activity AS (
    SELECT
        user_id,
        COUNT(DISTINCT activity_date) AS active_days
    FROM activity
    GROUP BY user_id
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
        WHEN p.payment_count IS NULL THEN '비결제자'
        WHEN p.payment_count = 1 THEN '1회 결제자'
        ELSE '반복 결제자'
    END AS payment_group,

    COUNT(*) AS users,

    ROUND(
        AVG(a.active_days),
        2
    ) AS avg_active_days

FROM user_activity a
LEFT JOIN payment_summary p
    ON a.user_id = p.user_id
GROUP BY payment_group;
-- '비결제자','204253','2.64'
-- '1회 결제자','18584','2.79'
-- '반복 결제자','8016','3.12'

-- ------
-- 요약 --
-- ------
-- [D7 리텐션 비교]
-- 비결제자   : 171,499명 / D7 10.16%
-- 1회 결제자 : 15,284명  / D7 11.25%
-- 반복 결제자 : 6,652명  / D7 12.91%

-- 비결제자 → 1회 결제자 → 반복 결제자 순으로
-- D7 리텐션이 점진적으로 증가하는 패턴이 확인됨.

-- 비결제자와 반복 결제자의 D7 리텐션 차이는 약 2.75%p이며,
-- 반복 구매 경험이 있는 사용자가 서비스에 더 오래 남는 경향이 나타남.

-- [평균 활동일 수 비교]
-- 비결제자   : 평균 2.64일
-- 1회 결제자 : 평균 2.79일
-- 반복 결제자 : 평균 3.12일

-- 평균 활동일 수 역시
-- 비결제자 → 1회 결제자 → 반복 결제자 순으로 증가함.

-- 따라서 결제 수준이 높을수록
-- 서비스 이용 지속성과 리텐션이 함께 높게 나타나는 경향이 확인됨.

-- 다만 현재 분석은 연관관계만 확인한 것으로,
-- 결제가 리텐션을 높이는 것인지,
-- 원래 활동성이 높은 사용자가 결제를 더 많이 하는 것인지는
-- 판단할 수 없음.

-- 추후에는 최초 결제 시점을 기준으로
-- 결제 이전 / 이후 활동 변화와 재방문 패턴을 비교하여
-- 시간적 선후관계를 더 명확하게 확인할 필요가 있음.