TRUNCATE TABLE
    fact_sales,
    dim_product,
    dim_store,
    dim_seller,
    dim_customer,
    dim_supplier,
    dim_brand,
    dim_product_category,
    dim_location,
    dim_pet,
    dim_pet_breed,
    dim_pet_category
RESTART IDENTITY CASCADE;


INSERT INTO dim_pet_category (pet_type, category_name)
SELECT DISTINCT ON (LOWER(customer_pet_type))
    LOWER(customer_pet_type),
    pet_category
FROM raw_sales
WHERE customer_pet_type IS NOT NULL
ORDER BY LOWER(customer_pet_type);


INSERT INTO dim_pet_breed (breed_name, pet_category_id)
SELECT DISTINCT r.customer_pet_breed, pc.pet_category_id
FROM raw_sales r
JOIN dim_pet_category pc ON pc.pet_type = LOWER(r.customer_pet_type)
WHERE r.customer_pet_breed IS NOT NULL
ON CONFLICT (breed_name, pet_category_id) DO NOTHING;


INSERT INTO dim_pet (pet_name, breed_id)
SELECT DISTINCT r.customer_pet_name, b.breed_id
FROM raw_sales r
JOIN dim_pet_category pc ON pc.pet_type = LOWER(r.customer_pet_type)
JOIN dim_pet_breed b ON b.breed_name = r.customer_pet_breed
                    AND b.pet_category_id = pc.pet_category_id
WHERE r.customer_pet_name IS NOT NULL
ON CONFLICT (pet_name, breed_id) DO NOTHING;


INSERT INTO dim_location (country, state, city, postal_code)
SELECT DISTINCT country, state, city, postal_code FROM (
    SELECT customer_country  AS country, NULL::text   AS state, NULL::text       AS city, customer_postal_code AS postal_code
    FROM raw_sales WHERE customer_country IS NOT NULL
    UNION
    SELECT seller_country, NULL::text, NULL::text, seller_postal_code
    FROM raw_sales WHERE seller_country IS NOT NULL
    UNION
    SELECT store_country, store_state, store_city, NULL::text
    FROM raw_sales WHERE store_country IS NOT NULL
    UNION
    SELECT supplier_country, NULL::text, supplier_city, NULL::text
    FROM raw_sales WHERE supplier_country IS NOT NULL
) all_locations;


INSERT INTO dim_product_category (category_name)
SELECT DISTINCT product_category
FROM raw_sales
WHERE product_category IS NOT NULL
ON CONFLICT (category_name) DO NOTHING;


INSERT INTO dim_brand (brand_name)
SELECT DISTINCT product_brand
FROM raw_sales
WHERE product_brand IS NOT NULL
ON CONFLICT (brand_name) DO NOTHING;


INSERT INTO dim_supplier (supplier_name, contact_name, email, phone, address, location_id)
SELECT DISTINCT ON (r.supplier_name, r.supplier_email)
    r.supplier_name,
    r.supplier_contact,
    r.supplier_email,
    r.supplier_phone,
    r.supplier_address,
    l.location_id
FROM raw_sales r
JOIN dim_location l ON l.country    =                  r.supplier_country
                   AND l.city       IS NOT DISTINCT FROM r.supplier_city
                   AND l.state      IS NULL
                   AND l.postal_code IS NULL
WHERE r.supplier_name IS NOT NULL
ON CONFLICT (supplier_name, email) DO NOTHING;


INSERT INTO dim_customer (first_name, last_name, age, email, location_id, pet_id)
SELECT DISTINCT ON (r.customer_email)
    r.customer_first_name,
    r.customer_last_name,
    NULLIF(r.customer_age, '')::int,
    r.customer_email,
    l.location_id,
    p.pet_id
FROM raw_sales r
JOIN dim_location l ON l.country     =                  r.customer_country
                   AND l.postal_code IS NOT DISTINCT FROM r.customer_postal_code
                   AND l.state       IS NULL
                   AND l.city        IS NULL
LEFT JOIN dim_pet_category pc ON pc.pet_type = LOWER(r.customer_pet_type)
LEFT JOIN dim_pet_breed   pb ON pb.breed_name      = r.customer_pet_breed
                            AND pb.pet_category_id = pc.pet_category_id
LEFT JOIN dim_pet          p ON p.pet_name = r.customer_pet_name
                            AND p.breed_id = pb.breed_id
WHERE r.customer_email IS NOT NULL
ON CONFLICT (email) DO NOTHING;


INSERT INTO dim_seller (first_name, last_name, email, location_id)
SELECT DISTINCT ON (r.seller_email)
    r.seller_first_name,
    r.seller_last_name,
    r.seller_email,
    l.location_id
FROM raw_sales r
JOIN dim_location l ON l.country     =                  r.seller_country
                   AND l.postal_code IS NOT DISTINCT FROM r.seller_postal_code
                   AND l.state       IS NULL
                   AND l.city        IS NULL
WHERE r.seller_email IS NOT NULL
ON CONFLICT (email) DO NOTHING;


INSERT INTO dim_store (store_name, store_location, phone, email, location_id)
SELECT DISTINCT ON (r.store_name, l.location_id)
    r.store_name,
    r.store_location,
    r.store_phone,
    r.store_email,
    l.location_id
FROM raw_sales r
JOIN dim_location l ON l.country     =                  r.store_country
                   AND l.state       IS NOT DISTINCT FROM r.store_state
                   AND l.city        IS NOT DISTINCT FROM r.store_city
                   AND l.postal_code IS NULL
WHERE r.store_name IS NOT NULL
ON CONFLICT (store_name, location_id) DO NOTHING;


INSERT INTO dim_product (
    product_name, description, price, weight, color, size, material,
    rating, reviews, release_date, expiry_date,
    product_category_id, brand_id, supplier_id
)
SELECT DISTINCT ON (r.product_name, b.brand_id)
    r.product_name,
    r.product_description,
    NULLIF(r.product_price,  '')::numeric,
    NULLIF(r.product_weight, '')::numeric,
    r.product_color,
    r.product_size,
    r.product_material,
    NULLIF(r.product_rating,  '')::numeric,
    NULLIF(r.product_reviews, '')::int,
    TO_DATE(NULLIF(r.product_release_date, ''), 'MM/DD/YYYY'),
    TO_DATE(NULLIF(r.product_expiry_date,  ''), 'MM/DD/YYYY'),
    pc.product_category_id,
    b.brand_id,
    s.supplier_id
FROM raw_sales r
JOIN dim_product_category pc ON pc.category_name = r.product_category
JOIN dim_brand            b  ON b.brand_name     = r.product_brand
JOIN dim_supplier         s  ON s.supplier_name  = r.supplier_name
                            AND s.email IS NOT DISTINCT FROM r.supplier_email
WHERE r.product_name IS NOT NULL
ON CONFLICT (product_name, brand_id) DO NOTHING;


INSERT INTO fact_sales (sale_date, customer_id, seller_id, product_id, store_id, quantity, total_price)
SELECT
    TO_DATE(r.sale_date, 'MM/DD/YYYY'),
    c.customer_id,
    sl.seller_id,
    p.product_id,
    st.store_id,
    NULLIF(r.sale_quantity,    '')::int,
    NULLIF(r.sale_total_price, '')::numeric
FROM raw_sales r
JOIN dim_customer c  ON c.email  = r.customer_email
JOIN dim_seller   sl ON sl.email = r.seller_email
JOIN dim_brand    b  ON b.brand_name  = r.product_brand
JOIN dim_product  p  ON p.product_name = r.product_name
                    AND p.brand_id     = b.brand_id
JOIN dim_location l_store ON l_store.country     =                  r.store_country
                         AND l_store.state       IS NOT DISTINCT FROM r.store_state
                         AND l_store.city        IS NOT DISTINCT FROM r.store_city
                         AND l_store.postal_code IS NULL
JOIN dim_store st ON st.store_name  = r.store_name
                 AND st.location_id = l_store.location_id;
