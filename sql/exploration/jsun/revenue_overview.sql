-- =========================================
-- revenue_overview.sql
-- 목적:
-- 1. 결제 데이터 구조 파악
-- 2. 결제 사용자 특성 파악
-- 3. 결제 전 행동 탐색
-- 4. 매출 극대화 관련 세부 주제 후보 도출
-- =========================================

-- =========================================
-- A. 결제 데이터 기본 현황
-- =========================================

-- 1. 전체 결제 건수
SELECT COUNT(*) AS payment_count
FROM final.accounts_paymenthistory;
-- 95,140건

-- 2. 결제 사용자 수
SELECT COUNT(DISTINCT user_id) AS paying_users
FROM final.accounts_paymenthistory;
-- 59,192명

-- 3. 사용자별 결제 횟수
SELECT
    user_id,
    COUNT(*) AS payment_count
FROM final.accounts_paymenthistory
GROUP BY user_id
ORDER BY payment_count DESC;
-- 한 사용자의 최대 결제 횟수 : 60건 (user_id: 1527451)

-- 4. 상품별 결제 횟수
SELECT
    productId,
    COUNT(*) AS payment_count,
    COUNT(DISTINCT user_id) AS paying_users
FROM final.accounts_paymenthistory
GROUP BY productId
ORDER BY payment_count DESC;

-- 'heart.777','57873','57432'
-- 'heart.1000','19309','11124'
-- 'heart.200','15822','9383'
-- 'heart.4000','2136','1501'

-- 5. OS별 결제
SELECT
    phone_type,
    COUNT(*) AS payment_count,
    COUNT(DISTINCT user_id) AS paying_users
FROM final.accounts_paymenthistory
GROUP BY phone_type;
-- 'A','33508','21945'
-- 'I','61632','37303'

-- ------
-- 요약 --
-- ------
-- 전체 결제 건수: 95,140건
-- 결제 경험 사용자: 59,192명
-- 결제 사용자당 평균 결제 횟수: 약 1.61회
-- 최대 결제 횟수: 60회 (user_id = 1527451)

-- 상품별 결제
-- heart.777  : 57,873건 / 57,432명 / 사용자당 약 1.01회
-- heart.1000 : 19,309건 / 11,124명 / 사용자당 약 1.74회
-- heart.200  : 15,822건 / 9,383명  / 사용자당 약 1.69회
-- heart.4000 : 2,136건  / 1,501명  / 사용자당 약 1.42회

-- heart.777이 전체 결제 건수의 약 60.8%를 차지함.
-- 다만 사용자당 결제 횟수는 거의 1회로 나타남.
-- 반대로 heart.1000, heart.200은 반복 구매 비중이 상대적으로
-- 높을 가능성이 있어 구매 순서 및 재구매 패턴 추가 확인 필요.

-- OS별 결제
-- Android(A): 33,508건 / 21,945명 / 사용자당 약 1.53회
-- iOS(I)   : 61,632건 / 37,303명 / 사용자당 약 1.65회

-- 단, OS별 전체 사용자 수를 아직 고려하지 않았기 때문에
-- iOS의 결제 성향이 더 높다고 해석할 수 없음.
-- 이후 OS별 전체 사용자 대비 결제 전환율 확인 필요.


-- =========================================
-- B. 결제 성공 / 실패 현황
-- =========================================

-- 6. 결제 성공 / 실패 전체 건수 비교
SELECT
    'success' AS payment_status,
    COUNT(*) AS payment_count,
    COUNT(DISTINCT user_id) AS user_count
FROM final.accounts_paymenthistory

UNION ALL

SELECT
    'fail' AS payment_status,
    COUNT(*) AS payment_count,
    COUNT(DISTINCT user_id) AS user_count
FROM final.accounts_failpaymenthistory;
-- 'success','95140','59192'
-- 'fail','163','160'

-- 7. 상품별 결제 성공 / 실패 및 총 결제 시도 건수
SELECT
    productId,
    SUM(success_count) AS success_count,
    SUM(fail_count) AS fail_count,
    SUM(success_count) + SUM(fail_count) AS total_count
FROM (
    SELECT
        productId,
        COUNT(*) AS success_count,
        0 AS fail_count
    FROM final.accounts_paymenthistory
    GROUP BY productId

    UNION ALL

    SELECT
        productId,
        0 AS success_count,
        COUNT(*) AS fail_count
    FROM final.accounts_failpaymenthistory
    GROUP BY productId
) t
GROUP BY productId
ORDER BY total_count DESC;
-- 'heart.777','57873','49','57922'
-- 'heart.1000','19309','4','19313'
-- 'heart.200','15822','3','15825'
-- 'heart.4000','2136','0','2136'
-- NULL,'0','107','107'


-- 8. 상품별 결제 실패율
SELECT
    productId,
    success_count,
    fail_count,
    ROUND(
        100.0 * fail_count / (success_count + fail_count),
        2
    ) AS fail_rate
FROM (
    SELECT
        productId,
        SUM(success_count) AS success_count,
        SUM(fail_count) AS fail_count
    FROM (
        SELECT
            productId,
            COUNT(*) AS success_count,
            0 AS fail_count
        FROM final.accounts_paymenthistory
        GROUP BY productId

        UNION ALL

        SELECT
            productId,
            0 AS success_count,
            COUNT(*) AS fail_count
        FROM final.accounts_failpaymenthistory
        GROUP BY productId
    ) x
    GROUP BY productId
) y
ORDER BY fail_rate DESC;
-- NULL,'0','107','100.00'
-- 'heart.777','57873','49','0.08'
-- 'heart.200','15822','3','0.02'
-- 'heart.1000','19309','4','0.02'
-- 'heart.4000','2136','0','0.00'

-- 9. OS별 결제 성공 / 실패
SELECT
    phone_type,
    SUM(success_count) AS success_count,
    SUM(fail_count) AS fail_count,
    ROUND(
        100.0 * SUM(fail_count)
        / (SUM(success_count) + SUM(fail_count)),
        2
    ) AS fail_rate
FROM (
    SELECT
        phone_type,
        COUNT(*) AS success_count,
        0 AS fail_count
    FROM final.accounts_paymenthistory
    GROUP BY phone_type

    UNION ALL

    SELECT
        phone_type,
        0 AS success_count,
        COUNT(*) AS fail_count
    FROM final.accounts_failpaymenthistory
    GROUP BY phone_type
) t
GROUP BY phone_type;
-- 'A','33508','56','0.17'
-- 'I','61632','107','0.17'

-- ------
-- 요약 --
-- ------
-- 전체 결제 성공: 95,140건
-- 전체 결제 실패: 163건
-- 전체 결제 시도 대비 실패율: 약 0.17%

-- 상품이 정상적으로 식별된 결제 실패는 총 56건으로 매우 적음.
-- heart.777  : 실패율 0.08%
-- heart.1000 : 실패율 0.02%
-- heart.200  : 실패율 0.02%
-- heart.4000 : 실패율 0.00%

-- 결제 실패 163건 중 107건은 productId가 NULL로 기록됨.
-- 실제 상품별 결제 실패보다 productId NULL 실패가 더 큰 비중을 차지하므로
-- 해당 데이터의 발생 원인 또는 로그 수집 구조를 추가 확인할 필요가 있음.

-- OS별 실패율
-- Android(A): 0.17%
-- iOS(I)    : 0.17%
-- 두 OS 간 결제 실패율 차이는 거의 없음.

-- 현재 결과만 보면 정상 상품의 결제 실패율이 매우 낮기 때문에
-- '결제 실패 개선' 자체를 매출 극대화의 주요 세부 주제로 보기에는
-- 우선순위가 낮아 보임.


-- =========================================
-- C. 최초 결제 / 반복 결제
-- =========================================

-- 10. 결제 횟수별 사용자 분포
WITH user_payment AS (
    SELECT
        user_id,
        COUNT(*) AS payment_count
    FROM final.accounts_paymenthistory
    GROUP BY user_id
)

SELECT
    CASE
        WHEN payment_count = 1 THEN '1회'
        WHEN payment_count = 2 THEN '2회'
        WHEN payment_count BETWEEN 3 AND 5 THEN '3~5회'
        WHEN payment_count BETWEEN 6 AND 10 THEN '6~10회'
        ELSE '11회 이상'
    END AS payment_group,
    COUNT(*) AS user_count
FROM user_payment
GROUP BY payment_group
ORDER BY MIN(payment_count);
-- '1회','43049'
-- '2회','8582'
-- '3~5회','6007'
-- '6~10회','1271'
-- '11회 이상','283'

-- 11. 상품별 1회 구매자 / 반복 구매자
WITH product_user_payment AS (
    SELECT
        productId,
        user_id,
        COUNT(*) AS payment_count
    FROM final.accounts_paymenthistory
    GROUP BY productId, user_id
)

SELECT
    productId,
    SUM(CASE WHEN payment_count = 1 THEN 1 ELSE 0 END) AS one_time_users,
    SUM(CASE WHEN payment_count >= 2 THEN 1 ELSE 0 END) AS repeat_users,
    ROUND(
        100.0 * SUM(CASE WHEN payment_count >= 2 THEN 1 ELSE 0 END)
        / COUNT(*),
        2
    ) AS repeat_user_rate
FROM product_user_payment
GROUP BY productId
ORDER BY repeat_user_rate DESC;
-- 'heart.200','6015','3368','35.89'
-- 'heart.1000','7272','3852','34.63'
-- 'heart.4000','1174','327','21.79'
-- 'heart.777','57059','373','0.65'

-- 12. 사용자별 최초 구매 상품
WITH first_payment AS (
    SELECT
        user_id,
        productId,
        created_at,
        ROW_NUMBER() OVER (
            PARTITION BY user_id
            ORDER BY created_at
        ) AS rn
    FROM final.accounts_paymenthistory
)

SELECT
    productId,
    COUNT(*) AS first_purchase_users
FROM first_payment
WHERE rn = 1
GROUP BY productId
ORDER BY first_purchase_users DESC;
-- 'heart.777','55703'
-- 'heart.1000','2400'
-- 'heart.200','588'
-- 'heart.4000','501'

-- ---------
-- -- 요약 --
-- ---------
-- 전체 결제 사용자 59,192명 중
-- 1회 결제자는 43,049명으로 약 72.7%를 차지함.
-- 따라서 결제 경험자의 대부분이 1회 결제 후 추가 구매로 이어지지 않는 구조가 나타남.

-- 결제 횟수별 사용자 분포
-- 1회       : 43,049명
-- 2회       : 8,582명
-- 3~5회     : 6,007명
-- 6~10회    : 1,271명
-- 11회 이상 : 283명

-- 상품별 반복 구매율
-- heart.200  : 35.89%
-- heart.1000 : 34.63%
-- heart.4000 : 21.79%
-- heart.777  : 0.65%

-- heart.200, heart.1000은 동일 상품의 반복 구매 비율이 상대적으로 높음.
-- 반면 heart.777은 반복 구매율이 매우 낮아 1회성 구매 성격이 강하게 나타남.

-- 최초 구매 상품
-- heart.777  : 55,703명
-- heart.1000 : 2,400명
-- heart.200  : 588명
-- heart.4000 : 501명

-- 전체 결제 사용자 중 약 94.1%가 heart.777을 최초 구매함.
-- 따라서 heart.777이 최초 결제 진입 상품 역할을 할 가능성이 매우 높아 보임.
-- 다만 실제 상품 정책/가격/프로모션 여부를 확인해야 정확한 해석이 가능함.

-- 현재 결과를 보면 신규 결제자 확보뿐 아니라
-- 1회 결제자를 반복 구매자로 전환시키는 전략이
-- 매출 극대화 관점에서 중요한 분석 주제가 될 가능성이 있음.


-- =========================================
-- D. 시간에 따른 결제 패턴
-- =========================================

-- 13. 일별 결제 건수
SELECT
    DATE(created_at) AS payment_date,
    COUNT(*) AS payment_count,
    COUNT(DISTINCT user_id) AS paying_users
FROM final.accounts_paymenthistory
GROUP BY DATE(created_at)
ORDER BY payment_date;

-- 14. 요일별 결제 건수
SELECT
    DAYOFWEEK(created_at) AS day_num,
    DAYNAME(created_at) AS day_name,
    COUNT(*) AS payment_count,
    COUNT(DISTINCT user_id) AS paying_users
FROM final.accounts_paymenthistory
GROUP BY DAYOFWEEK(created_at), DAYNAME(created_at)
ORDER BY day_num;
-- '1','Sunday','23612','18194'
-- '2','Monday','15474','12074'
-- '3','Tuesday','14451','11287'
-- '4','Wednesday','11620','9077'
-- '5','Thursday','9653','7588'
-- '6','Friday','8877','6876'
-- '7','Saturday','11453','8762'

-- 15. 시간대별 결제 건수
SELECT
    HOUR(created_at) AS payment_hour,
    COUNT(*) AS payment_count,
    COUNT(DISTINCT user_id) AS paying_users
FROM final.accounts_paymenthistory
GROUP BY HOUR(created_at)
ORDER BY payment_hour;
-- '0','1525','1345'
-- '1','2004','1739'
-- '2','2193','1931'
-- '3','2520','2174'
-- '4','3143','2741'
-- '5','3337','2913'
-- '6','3805','3293'
-- '7','4918','4238'
-- '8','5818','4881'
-- '9','5900','5001'
-- '10','6089','5142'
-- '11','6874','5768'
-- '12','8266','6812'
-- '13','10068','8308'
-- '14','9911','8107'
-- '15','7847','6486'
-- '16','4222','3532'
-- '17','1530','1265'
-- '18','671','542'
-- '19','291','246'
-- '20','191','170'
-- '21','471','395'
-- '22','1605','1386'
-- '23','1941','1719'
-- 뭔가 UTC 시간이 의심되긴 함.

-- 위 결과가 UTC기준 이라고 했을 때, KST 기준 시간대별 결제 건수
SELECT
    HOUR(DATE_ADD(created_at, INTERVAL 9 HOUR)) AS payment_hour_kst,
    COUNT(*) AS payment_count,
    COUNT(DISTINCT user_id) AS paying_users
FROM final.accounts_paymenthistory
GROUP BY HOUR(DATE_ADD(created_at, INTERVAL 9 HOUR))
ORDER BY payment_hour_kst;
-- '0','7847','6486'
-- '1','4222','3532'
-- '2','1530','1265'
-- '3','671','542'
-- '4','291','246'
-- '5','191','170'
-- '6','471','395'
-- '7','1605','1386'
-- '8','1941','1719'
-- '9','1525','1345'
-- '10','2004','1739'
-- '11','2193','1931'
-- '12','2520','2174'
-- '13','3143','2741'
-- '14','3337','2913'
-- '15','3805','3293'
-- '16','4918','4238'
-- '17','5818','4881'
-- '18','5900','5001'
-- '19','6089','5142'
-- '20','6874','5768'
-- '21','8266','6812'
-- '22','10068','8308'
-- '23','9911','8107'

-- 일별 결제 KST 기준
SELECT
    DATE(DATE_ADD(created_at, INTERVAL 9 HOUR)) AS payment_date_kst,
    COUNT(*) AS payment_count,
    COUNT(DISTINCT user_id) AS paying_users
FROM final.accounts_paymenthistory
GROUP BY DATE(DATE_ADD(created_at, INTERVAL 9 HOUR))
ORDER BY payment_date_kst;

-- 요일별 결제 KST 기준
SELECT
    DAYOFWEEK(DATE_ADD(created_at, INTERVAL 9 HOUR)) AS day_num,
    DAYNAME(DATE_ADD(created_at, INTERVAL 9 HOUR)) AS day_name,
    COUNT(*) AS payment_count,
    COUNT(DISTINCT user_id) AS paying_users
FROM final.accounts_paymenthistory
GROUP BY
    DAYOFWEEK(DATE_ADD(created_at, INTERVAL 9 HOUR)),
    DAYNAME(DATE_ADD(created_at, INTERVAL 9 HOUR))
ORDER BY day_num;
-- '1','Sunday','22465','17401'
-- '2','Monday','16199','12569'
-- '3','Tuesday','15011','11758'
-- '4','Wednesday','12066','9451'
-- '5','Thursday','9920','7747'
-- '6','Friday','9098','7123'
-- '7','Saturday','10381','7923'

-- ---------
-- -- 요약 --
-- ---------
-- 결제 데이터의 created_at은 UTC 저장 가능성이 높아
-- KST(+9시간) 기준으로 변환하여 일별/요일별 패턴을 재확인함.

-- [일별 결제]
-- KST 기준으로도 2023년 5월 중순에 결제가 매우 집중되어 있음.
-- 특히 2023-05-14에 11,454건 / 9,337명으로 가장 높은 결제 활동이 확인됨.
-- 이후 5월 말부터 결제량이 빠르게 감소하며,
-- 6월 중순 이후에는 대부분 일별 결제가 수십~수백 건 수준으로 낮아짐.

-- 7~8월 일부 날짜에서는 주변 날짜 대비 일시적인 결제 증가가 나타남.
-- 예: 7/11~7/13, 7/20~7/21, 7/27~7/29, 8/4~8/6
-- 해당 날짜의 사용자 유입, 이벤트, 프로모션 등의 영향 여부를
-- 추가 확인할 필요가 있음.


-- [요일별 결제 - KST 기준]
-- Sunday    : 22,465건 / 17,401명
-- Monday    : 16,199건 / 12,569명
-- Tuesday   : 15,011건 / 11,758명
-- Wednesday : 12,066건 / 9,451명
-- Thursday  : 9,920건  / 7,747명
-- Friday    : 9,098건  / 7,123명
-- Saturday  : 10,381건 / 7,923명

-- Sunday의 결제 건수와 결제 사용자 수가 가장 높게 나타남.
-- 다만 2023-05-14의 결제가 매우 큰 비중을 차지하므로,
-- 이를 단순한 '요일 효과'로 해석하기는 어려움.
-- 특정 날짜의 대규모 결제가 Sunday 집계에 영향을 주었을 가능성이 큼.

-- 따라서 향후 요일별 결제 성향을 비교할 경우
-- 1) 초기 대량 결제 기간을 제외한 비교
-- 2) 요일별 활성 사용자 대비 결제율
-- 등을 함께 확인할 필요가 있음.


-- [시간대]
-- created_at을 UTC로 저장했다고 가정하면
-- 기존 UTC 기준 12~15시 피크는 KST 기준 21~00시에 해당함.
-- 기존 UTC 기준 18~21시의 낮은 결제량은 KST 기준 03~06시에 해당함.

-- 이는 서비스 대상이 중·고등학생이라는 점을 고려할 때
-- 저녁~자정 결제가 많고 새벽 시간대 결제가 적은 패턴으로 해석할 수 있어
-- UTC 저장 가능성이 높아 보임.

-- 단, 실제 저장 시간대는 DB/백엔드 설정을 확인하여 확정할 필요가 있음.


-- ★ 중요
-- accounts_paymenthistory 관측 기간:
-- 2023-05-13 ~ 2024-05-08

-- Hackle 이벤트 로그 관측 기간:
-- 2023-07-18 ~ 2023-08-10

-- 따라서 향후 결제 전 행동과 결제를 연결할 경우,
-- Hackle 관측 기간 내 결제만 별도로 추출하여 분석해야 함.

-- 전체 결제 데이터:
-- 최초 구매 / 반복 구매 / 상품별 구매 구조 / 장기 결제 패턴 분석

-- Hackle 기간 결제 데이터:
-- 세션 / 투표 / 친구 / 질문 행동 등 결제 전 행동 분석