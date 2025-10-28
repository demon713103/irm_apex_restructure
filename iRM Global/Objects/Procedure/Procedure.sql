create or replace PROCEDURE CALL_WCC (P_TITLE IN VARCHAR2)

AS

l_user_name VARCHAR2(100) := 'FUSION_AUDIT_USER';

l_password VARCHAR2(100) := 'Fusion_audit_2025';

l_ws_url VARCHAR2(500) := 'http://fa-ewzx-dev1-saasfaprod1.fa.ocs.oraclecloud.com/idcws/GenericSoapPort?wsdl';

l_ws_action VARCHAR2(500) := 'urn:GenericSoap/GenericSoapOperation';

l_ws_response_clob CLOB;

l_ws_response_clob_clean CLOB;

l_ws_envelope CLOB;

l_http_status VARCHAR2(100);

v_dID VARCHAR2(100);

l_ws_resp_xml XMLTYPE;

l_start_xml PLS_INTEGER;

l_end_xml PLS_INTEGER;

l_resp_len PLS_INTEGER;

l_xml_len PLS_INTEGER;

clob_l_start_xml PLS_INTEGER;

clob_l_resp_len PLS_INTEGER;

clob_l_xml_len PLS_INTEGER;

clean_clob_l_end_xml PLS_INTEGER;

clean_clob_l_resp_len PLS_INTEGER;

clean_clob_l_xml_len PLS_INTEGER;

v_cdata VARCHAR2(100);

v_length INTEGER;

BEGIN

l_ws_envelope :=

'<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:ucm="http://www.oracle.com/UCM">

<soapenv:Body>

<ucm:GenericRequest webKey="cs">

<ucm:Service IdcService="GET_SEARCH_RESULTS">

<ucm:Document>

<ucm:Field name="QueryText">dDocTitle &lt;starts&gt;`'|| P_TITLE ||'`</ucm:Field>

</ucm:Document>

</ucm:Service>

</ucm:GenericRequest>

</soapenv:Body>

</soapenv:Envelope>';

apex_web_service.g_request_headers(1).name := 'SOAPAction';

apex_web_service.g_request_headers(1).value := l_ws_action;

apex_web_service.g_request_headers(2).name := 'Content-Type';

apex_web_service.g_request_headers(2).value := 'text/xml; charset=UTF-8';

l_ws_response_clob := apex_web_service.make_rest_request(

p_url => l_ws_url,

p_http_method => 'POST',

p_body => l_ws_envelope,

p_username => l_user_name,

p_password => l_password);

--Remove header as it is not XML

clob_l_start_xml := INSTR(l_ws_response_clob,'<env',1,1);

clob_l_resp_len := LENGTH(l_ws_response_clob);

clob_l_xml_len := clob_l_resp_len - clob_l_start_xml + 1;

l_ws_response_clob_clean := dbms_lob.substr(l_ws_response_clob,clob_l_xml_len,clob_l_start_xml);

--Remove the tail as it is not XML

clean_clob_l_end_xml := INSTR(l_ws_response_clob_clean,'------=',1,1);

clean_clob_l_resp_len := LENGTH(l_ws_response_clob_clean);

clean_clob_l_xml_len := clean_clob_l_end_xml - 1;

l_ws_response_clob_clean := dbms_lob.substr(l_ws_response_clob_clean,clean_clob_l_xml_len,1);

--Convert CLOB to XMLTYPE

l_ws_resp_xml := XMLTYPE(l_ws_response_clob_clean);

--insert the first row and comment this line after first row is inserted.

--insert into xml_key VALUES (1, l_ws_response_clob_clean);

    -- Update the existing row so that the result is the latest resultset

    UPDATE xml_key

   SET xml = l_ws_response_clob_clean;

    -- Add your condition here to specify which row to update

    COMMIT; -- Commit the transaction

END;
/
create or replace PROCEDURE PROC_DYNAMIC_NAVIGATION( 
    p_app_id IN NUMBER, 
    p_app_user IN VARCHAR2, 
    p_result OUT SYS_REFCURSOR -- OUT parameter to return the result set 
) 
AS 
BEGIN 
    -- Open the cursor for the dynamic SQL query 
    OPEN p_result FOR 
        'SELECT level, 
                MODULE_NAME AS ENTRY_TEXT, 
                (CASE WHEN page_no IS NOT NULL 
                      THEN ''f?p='' || APP_NO || '':'' || PAGE_NO || '':'' || :APP_SESSION 
                      ELSE NULL 
                 END) AS target, 
                PAGE_NO, 
                ICON, 
                ID, 
                PARENT_ID 
         FROM MST_APP_NAVIGATION CNM 
         WHERE CNM.is_active = ''Y'' 
           AND FN_CUSTOM_NAV_AUTH(:p_app_user, ID, PARENT_ID) = ''TRUE'' 
           AND APP_NO = :p_app_id 
         START WITH parent_id IS NULL 
         CONNECT BY PRIOR CNM.ID = PARENT_ID 
         ORDER SIBLINGS BY SEQ' 
    USING p_app_user, p_app_id; -- Bind variables for the dynamic SQL 
END PROC_DYNAMIC_NAVIGATION;
/
create or replace PROCEDURE PR_SHAREPOINT_REINVITE_USERS_V1 (
  P_APP_USER         IN VARCHAR2,
  P_REINVITE_IDS     IN VARCHAR2, 
  P_PERMISSION       IN  VARCHAR2 DEFAULT 'WRITE', 
  P_SITE_ID          IN VARCHAR2,
  P_DRIVE_ID         IN VARCHAR2,
  P_ITEM_ID          IN VARCHAR2
)
AS
  l_token_response     CLOB;
  l_token_json         apex_json.t_values;
  l_token              VARCHAR2(4000);
  l_invite_response    CLOB;
  l_html               VARCHAR2(4000) := '';
  l_policy_owner       VARCHAR2(2000);
  l_key_contract_ids   APEX_T_VARCHAR2;
  l_recipient_email    VARCHAR2(2000);
  l_permission_id      VARCHAR2(1000);
  l_granted_to         VARCHAR2(4000);
  l_response_json      CLOB;
  l_response_values    apex_json.t_values;
  l_client_id          VARCHAR2(2000);
  l_client_secret      VARCHAR2(2000);
  l_scope              VARCHAR2(1000);
BEGIN
  -- Get client credentials
  SELECT CLIENT_ID, CLIENT_SECRET, SCOPE 
    INTO l_client_id, l_client_secret, l_scope 
    FROM IRM_GLOBAL_APP_CONFIG.MST_MICROSOFT_ENTRA_CREDENTIALS;

  -- Start JSON with current user
  l_html := '[{"email": "' || REPLACE(P_APP_USER, '"', '\"') || '"}';

  -- Build recipient list
  IF P_REINVITE_IDS IS NOT NULL THEN
    l_key_contract_ids := APEX_STRING.SPLIT(P_REINVITE_IDS, ':');
  ELSE
    -- If NULL, fetch all active, non-ERP users
    SELECT ID
      BULK COLLECT INTO l_key_contract_ids
      FROM IRM_GLOBAL_APP_CONFIG.MST_USERS
     WHERE IS_ACTIVE = 'Y'
       AND IS_ONLY_ERP_USERS = 'N';
  END IF;

  -- Loop over IDs and build JSON array
  FOR i IN 1 .. l_key_contract_ids.COUNT LOOP
    BEGIN
      SELECT EMAIL INTO l_recipient_email
        FROM IRM_GLOBAL_APP_CONFIG.MST_USERS
       WHERE ID = l_key_contract_ids(i);
      l_html := l_html || ', {"email": "' || REPLACE(l_recipient_email, '"', '\"') || '"}';
    EXCEPTION
      WHEN NO_DATA_FOUND THEN NULL;
    END;
  END LOOP;
  l_html := l_html || ']';




  -- Get OAuth token
  apex_web_service.g_request_headers.delete;
  apex_web_service.g_request_headers(1).name  := 'Content-Type';
  apex_web_service.g_request_headers(1).value := 'application/x-www-form-urlencoded';

  l_token_response := apex_web_service.make_rest_request(
    p_url         => 'https://login.microsoftonline.com/ffd87c9b-d203-42db-a8c1-16909eaafe2d/oauth2/v2.0/token',
    p_http_method => 'POST',
    p_body        => 'grant_type=client_credentials' ||
                     '&client_id=' || l_client_id ||
                     '&client_secret=' || l_client_secret ||
                     '&scope=https://graph.microsoft.com/.default'
  );

  apex_json.parse(l_token_json, l_token_response);
  l_token := apex_json.get_varchar2(p_path => 'access_token', p_values => l_token_json);

  -- Set Authorization headers
  apex_web_service.g_request_headers.delete;
  apex_web_service.g_request_headers(1).name  := 'Authorization';
  apex_web_service.g_request_headers(1).value := 'Bearer ' || l_token;
  apex_web_service.g_request_headers(2).name  := 'Content-Type';
  apex_web_service.g_request_headers(2).value := 'application/json';

  --------------------------------------|| Revoke all existing permissions (except the current user) ||--------------------------------

--   l_response_json := apex_web_service.make_rest_request(
--     p_url         => 'https://graph.microsoft.com/v1.0/sites/' || P_SITE_ID || '/drives/' || P_DRIVE_ID || '/items/' || P_ITEM_ID || '/permissions',
--     p_http_method => 'GET'
--   );

--   apex_json.parse(l_response_values, l_response_json);
--   FOR i IN 1 .. apex_json.get_count(p_path => 'value', p_values => l_response_values) LOOP
--     BEGIN
--       l_permission_id := apex_json.get_varchar2(p_path => 'value[%d].id', p0 => i - 1, p_values => l_response_values);
--       l_granted_to := apex_json.get_varchar2(p_path => 'value[%d].grantedTo.user.displayName', p0 => i - 1, p_values => l_response_values);

--       IF LOWER(l_granted_to) <> LOWER(P_APP_USER) THEN
--         l_response_json := apex_web_service.make_rest_request(
--           p_url         => 'https://graph.microsoft.com/v1.0/sites/' || P_SITE_ID || '/drives/' || P_DRIVE_ID || '/items/' || P_ITEM_ID || '/permissions/' || l_permission_id,
--           p_http_method => 'DELETE'
--         );
--       END IF;
--     EXCEPTION WHEN OTHERS THEN NULL;
--     END;
--   END LOOP;

  ----------------------------------------- Revoke all existing permissions (except the current user) --------------------------------



  -- Invite recipients
  l_invite_response := apex_web_service.make_rest_request(
    p_url         => 'https://graph.microsoft.com/v1.0/sites/' || P_SITE_ID || '/drives/' || P_DRIVE_ID || '/items/' || P_ITEM_ID || '/invite',
    p_http_method => 'POST',
    p_body        => '{
      "recipients": ' || l_html || ',
      "message": "Here is the file you requested.",
      "requireSignIn": true,
      "sendInvitation": true,
      "roles": ["'||LOWER(P_PERMISSION) || '"]
    }'
  );

EXCEPTION
  WHEN OTHERS THEN
    APEX_ERROR.ADD_ERROR(
      p_message          => 'Error in PR_SHAREPOINT_REINVITE_USERS_V1: ' || SQLERRM,
      p_display_location => apex_error.c_inline_in_notification
    );
END PR_SHAREPOINT_REINVITE_USERS_V1;
/
create or replace PROCEDURE PR_SHAREPOINT_REMOVE_ALL_ACCESS_V1 (
  P_APP_USER  IN VARCHAR2,     
  P_SITE_ID   IN VARCHAR2,
  P_DRIVE_ID  IN VARCHAR2,    
  P_ITEM_ID   IN VARCHAR2      
)
AS
  l_token_response   CLOB;
  l_token_json       apex_json.t_values;
  l_token            VARCHAR2(4000);
  l_permission_id    VARCHAR2(1000);
  l_granted_to       VARCHAR2(4000);
  l_response_json    CLOB;
  l_response_values  apex_json.t_values;
  l_client_id        VARCHAR2(2000);
  l_client_secret    VARCHAR2(2000);
  l_scope            VARCHAR2(1000);
BEGIN
  -- Get client credentials
  SELECT CLIENT_ID, CLIENT_SECRET, SCOPE 
    INTO l_client_id, l_client_secret, l_scope 
    FROM IRM_GLOBAL_APP_CONFIG.MST_MICROSOFT_ENTRA_CREDENTIALS;

  -- Get OAuth token
  apex_web_service.g_request_headers.delete;
  apex_web_service.g_request_headers(1).name  := 'Content-Type';
  apex_web_service.g_request_headers(1).value := 'application/x-www-form-urlencoded';

  l_token_response := apex_web_service.make_rest_request(
    p_url         => 'https://login.microsoftonline.com/ffd87c9b-d203-42db-a8c1-16909eaafe2d/oauth2/v2.0/token',
    p_http_method => 'POST',
    p_body        => 'grant_type=client_credentials' ||
                     '&client_id=' || l_client_id ||
                     '&client_secret=' || l_client_secret ||
                     '&scope=https://graph.microsoft.com/.default'
  );

  apex_json.parse(l_token_json, l_token_response);
  l_token := apex_json.get_varchar2(p_path => 'access_token', p_values => l_token_json);

  -- Set headers
  apex_web_service.g_request_headers.delete;
  apex_web_service.g_request_headers(1).name  := 'Authorization';
  apex_web_service.g_request_headers(1).value := 'Bearer ' || l_token;
  apex_web_service.g_request_headers(2).name  := 'Content-Type';
  apex_web_service.g_request_headers(2).value := 'application/json';

  -- Get all permissions
  l_response_json := apex_web_service.make_rest_request(
    p_url         => 'https://graph.microsoft.com/v1.0/sites/' || P_SITE_ID || 
                     '/drives/' || P_DRIVE_ID || 
                     '/items/' || P_ITEM_ID || '/permissions',
    p_http_method => 'GET'
  );

  apex_json.parse(l_response_values, l_response_json);

  FOR i IN 1 .. apex_json.get_count(p_path => 'value', p_values => l_response_values) LOOP
    BEGIN
      l_permission_id := apex_json.get_varchar2(p_path => 'value[%d].id', p0 => i - 1, p_values => l_response_values);
      l_granted_to := apex_json.get_varchar2(p_path => 'value[%d].grantedTo.user.displayName', p0 => i - 1, p_values => l_response_values);

-- Revoke all except the current user
IF LOWER(l_granted_to) <> LOWER(P_APP_USER) THEN
  l_response_json := apex_web_service.make_rest_request(
    p_url         => 'https://graph.microsoft.com/v1.0/sites/' || P_SITE_ID || 
                     '/drives/' || P_DRIVE_ID || 
                     '/items/' || P_ITEM_ID || '/permissions/' || l_permission_id,
    p_http_method => 'DELETE'
  );
END IF;

    EXCEPTION
      WHEN OTHERS THEN
        NULL;
    END;
  END LOOP;

EXCEPTION
  WHEN OTHERS THEN
    APEX_ERROR.ADD_ERROR(
      p_message          => 'Error in PR_SHAREPOINT_REMOVE_ALL_ACCESS_V1: ' || SQLERRM,
      p_display_location => apex_error.c_inline_in_notification
    );
END PR_SHAREPOINT_REMOVE_ALL_ACCESS_V1;
/
create or replace PROCEDURE SP_DDL_MIGRATION_SCRIPT 
( 
    p_table_name IN varchar2 default null, 
    p_schema_name IN varchar2 default null 
) 
IS 
    v_error_log clob; 
BEGIN 
    FOR TBL_DDL IN( 
        SELECT ID, OBJECT_DDL, OBJECT_NAME FROM ALL_OBJECT_DDL  
        WHERE  
        -- CREATE_MANUALLY !='Y' AND IS_CREATED = 'N'  
        -- AND  
        SCHEMA_NAME = p_schema_name 
        AND OBJECT_TYPE = 'TABLE' 
        AND (p_table_name IS NULL OR OBJECT_NAME = p_table_name) 
    ) 
    LOOP 
        BEGIN 
            EXECUTE IMMEDIATE 'ALTER SESSION SET CURRENT_SCHEMA = '|| p_schema_name; 
            EXECUTE IMMEDIATE TBL_DDL.OBJECT_DDL; 
            EXECUTE IMMEDIATE 'ALTER SESSION SET CURRENT_SCHEMA = IRM_GLOBAL_APP_CONFIG'; 
 
            UPDATE ALL_OBJECT_DDL SET IS_CREATED = 'Y' WHERE ID = TBL_DDL.ID; 
        EXCEPTION WHEN OTHERS 
            THEN 
                v_error_log := 'Error for id '|| TBL_DDL.ID || ' : '|| SQLERRM; 
                DBMS_OUTPUT.PUT_LINE(v_error_log); 
 
                INSERT INTO ALL_DML_TABLE_LOGS(OBJECT_NAME,LOGS,IS_FROM_DDL) 
                VALUES(TBL_DDL.OBJECT_NAME, v_error_log,'From DDL'); 
        END; 
    END LOOP;  
end;
/
create or replace PROCEDURE SP_ERROR_LOGGER_V1 ( 
    p_client_id NUMBER DEFAULT 0, 
    p_username VARCHAR2 DEFAULT SYS_CONTEXT('APEX$SESSION','APP_USER'), 
    p_err_src VARCHAR2 DEFAULT NULL, --THE SOURCE OF THE ERROR OR WHERE THE ERROR OCCURED SUCH AS IF ITS A TRIGGER, PROCEDURE MENTION THE NAME OR IN ANY PAGE ETC 
    p_err_msg VARCHAR2 DEFAULT SQLERRM, --THE MESSEGE YOU WANT TO INSERT INTO THE TABLE AND SHOW IN THE PAGE LEVEL
    p_alert   VARCHAR2 DEFAULT 'N'
)  
AS 
BEGIN 
    -- Attempt to insert the error log 
    BEGIN 
        INSERT INTO IRM_GLOBAL_APP_CONFIG.TRN_ERROR_LOG ( 
            CLIENT_ID, 
            USER_NAME, 
            SOURCE, 
            ERROR_MESSEGE 
        ) 
        VALUES ( 
            p_client_id, 
            p_username, 
            p_err_src, 
            p_err_msg 
        ); 
 
     
    END; 
 
    IF p_alert = 'Y' THEN
        -- Log error in APEX if applicable 
        APEX_ERROR.ADD_ERROR ( 
            p_message  => p_err_msg, 
            p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION 
        ); 
    END IF;
 
 
END SP_ERROR_LOGGER_V1;
/
create or replace PROCEDURE SP_EXTRACT_ZIP_EBS( 
    p_schema_name     IN VARCHAR2, 
    p_data_source_id  IN NUMBER, 
    p_sync_header_id  IN NUMBER 
) 
AS 
    l_zip_file      BLOB; 
    l_unzipped_file BLOB; 
    l_files         apex_zip.t_files; 
    l_file_name     VARCHAR2(4000); 
    v_schema_name   VARCHAR2(1000); 
BEGIN 
    -- Fetch the ZIP file BLOB from the dynamic schema 
    EXECUTE IMMEDIATE 'SELECT FILE_BLOB FROM ' || p_schema_name || '.XX_EBS_DATASOURCE WHERE ID = :data_source_id' 
        INTO l_zip_file 
        USING p_data_source_id; 
 
    -- Extract files from the ZIP 
    l_files := apex_zip.get_files( 
        p_zipped_blob => l_zip_file, 
        p_only_files  => TRUE 
    ); 
    ---Update the status for each sync before file extraction--- 
    EXECUTE IMMEDIATE 'UPDATE '|| p_schema_name ||'.XX_EBS_SYNC_HEADER SET STATUS = ''File Extraction Started'' WHERE ID = :ID ' USING p_sync_header_id; 
 
    FOR i IN 1 .. l_files.COUNT LOOP 
        -- Get the content of each unzipped file 
        l_unzipped_file := apex_zip.get_file_content( 
            p_zipped_blob => l_zip_file, 
            p_file_name   => l_files(i) 
        ); 
         
        -- inserting in log table 
        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('First Process File Name inserted ' || l_files(i), 1, p_sync_header_id); 
        -- ends 
        COMMIT; 
 
        BEGIN 
            -- Extract the file name using REGEXP_SUBSTR 
            SELECT REGEXP_SUBSTR( 
                     l_files(i), 
                     '[^/]+$' 
                   )  
            INTO l_file_name 
            FROM DUAL; 
        EXCEPTION WHEN OTHERS 
            THEN 
                INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Error occured when extracting filename for : ' || l_files(i), 1, p_sync_header_id); 
                COMMIT; 
        END; 
 
        BEGIN 
            -- Insert the file name and content into the dynamic schema table 
            EXECUTE IMMEDIATE 'INSERT INTO ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES (SYNC_HEADER_ID, DATASOURCE_ID, FILE_NAME, FILE_BLOB) VALUES (:ID, :DATASOURCE_ID, :l_file_name, :l_unzipped_file)' 
                USING p_sync_header_id, p_data_source_id,l_file_name, l_unzipped_file; 
        EXCEPTION WHEN OTHERS 
            THEN 
                 
                INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Error occured for File Name inserted ' || l_files(i), 1, p_sync_header_id); 
                COMMIT; 
 
            EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occured in File Extraction'' WHERE ID = :ID' USING p_sync_header_id; 
        END; 
 
        -- Debugging output 
        -- DBMS_OUTPUT.PUT_LINE('File Name: ' || l_file_name); 
    END LOOP; 
    ---Update the status for each sync after file extraction--- 
    EXECUTE IMMEDIATE 'UPDATE '|| p_schema_name ||'.XX_EBS_SYNC_HEADER SET STATUS = ''File Extraction Finished'' WHERE ID = :ID ' USING p_sync_header_id; 
 
    COMMIT; 
END;
/
create or replace PROCEDURE SP_HEX_CODE_REMOVER_V1(
    p_table_name IN VARCHAR2
) AS
    v_sql           VARCHAR2(4000);
    v_column_name   VARCHAR2(128);
    v_data_type     VARCHAR2(128);
    v_rows_updated  NUMBER := 0;
    v_total_rows    NUMBER := 0;
    v_table_exists  NUMBER := 0;
    
    -- Cursor to get all character columns from the specified table
    CURSOR c_columns IS
        SELECT column_name, data_type
        FROM user_tab_columns
        WHERE table_name = UPPER(p_table_name)
        AND data_type IN ('VARCHAR2', 'CHAR', 'VARCHAR2', 'NCHAR', 'CLOB', 'NCLOB')
        ORDER BY column_id;
        
BEGIN
    -- Input validation
    IF p_table_name IS NULL OR LENGTH(TRIM(p_table_name)) = 0 THEN
        DBMS_OUTPUT.PUT_LINE('ERROR: Table name cannot be null or empty');
        RETURN;
    END IF;
    
    -- Check if table exists
    SELECT COUNT(*)
    INTO v_table_exists
    FROM user_tables
    WHERE table_name = UPPER(p_table_name);
    
    IF v_table_exists = 0 THEN
        DBMS_OUTPUT.PUT_LINE('ERROR: Table ' || UPPER(p_table_name) || ' does not exist or is not accessible');
        RETURN;
    END IF;
    
    DBMS_OUTPUT.PUT_LINE('Starting cleanup for table: ' || UPPER(p_table_name));
    DBMS_OUTPUT.PUT_LINE('=================================================');
    
    -- Loop through all character columns
    FOR rec IN c_columns LOOP
        v_column_name := rec.column_name;
        v_data_type := rec.data_type;
        
        -- Build dynamic SQL to update the column
        -- Remove both x000D and _x000D_ patterns
        v_sql := 'UPDATE ' || UPPER(p_table_name) || 
                 ' SET ' || v_column_name || ' = REPLACE(REPLACE(' || v_column_name || 
                 ', ''x000D'', ''''), ''_x000D_'', '''')' ||
                 ' WHERE ' || v_column_name || ' IS NOT NULL' ||
                 ' AND (' || v_column_name || ' LIKE ''%x000D%'' OR ' || 
                 v_column_name || ' LIKE ''%_x000D_%'')';
        
        -- Execute the update
        BEGIN
            EXECUTE IMMEDIATE v_sql;
            v_rows_updated := SQL%ROWCOUNT;
            v_total_rows := v_total_rows + v_rows_updated;
            
            IF v_rows_updated > 0 THEN
                DBMS_OUTPUT.PUT_LINE('Column: ' || LPAD(v_column_name, 30) || 
                                   ' (' || v_data_type || ') - Rows updated: ' || v_rows_updated);
            ELSE
                DBMS_OUTPUT.PUT_LINE('Column: ' || LPAD(v_column_name, 30) || 
                                   ' (' || v_data_type || ') - No data to clean');
            END IF;
            
        EXCEPTION
            WHEN OTHERS THEN
                DBMS_OUTPUT.PUT_LINE('ERROR processing column ' || v_column_name || ': ' || SQLERRM);
                ROLLBACK;
                RAISE;
        END;
        
    END LOOP;
    
    -- Commit the changes
    COMMIT;
    
    DBMS_OUTPUT.PUT_LINE('=================================================');
    DBMS_OUTPUT.PUT_LINE('Cleanup completed successfully!');
    DBMS_OUTPUT.PUT_LINE('Total rows updated across all columns: ' || v_total_rows);
    
    -- If no character columns found
    IF v_total_rows = 0 THEN
        DBMS_OUTPUT.PUT_LINE('Note: No character columns found or no data required cleaning');
    END IF;
    
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('=================================================');
        DBMS_OUTPUT.PUT_LINE('ERROR: Procedure failed with error: ' || SQLERRM);
        DBMS_OUTPUT.PUT_LINE('All changes have been rolled back.');
        RAISE;
        
END SP_HEX_CODE_REMOVER_V1;
/
create or replace PROCEDURE SP_SEND_MAIL_V1( 
    p_client_id NUMBER DEFAULT 0, --Client ID of the Sender 
    p_to VARCHAR2,--Recievevers mails or user ID seperated By ',' , ':' or '~' 
    p_cc VARCHAR2 DEFAULT NULL,--Sender mails or user ID seperated By ',' , ':' or '~' 
    p_subject VARCHAR2,--Subject of the mail 
    p_body CLOB,--The mail body of the mail 
    p_mail_type VARCHAR2 DEFAULT 'SINGLE'--The mail type 'BULK' or null : In Case of Sending all the mails to all users in a single mail and 'SINGLE' : in case of sending mail all the users individually 
) IS 

    v_to_users varchar2(4000) := replace(replace(p_to, ':', ','),'~', ','); 
    v_cc_users varchar2(4000) := replace(replace(p_cc, ':', ','),'~', ','); 
 
    v_to_user_mails varchar2(4000); 
    v_cc_user_mails varchar2(4000); 
    v_user_mail varchar2(320); 
    v_from_user varchar2(320); 
    v_first_name varchar2(1000); 
 
    v_user_id number; 
 
    v_response varchar2(4000); 
    v_body CLOB;
begin 
 
    v_response := v_response || 'Client ID : ' || p_client_id; 
 
    BEGIN 
 
        SELECT NO_REPLY_MAIL INTO v_from_user FROM IRM_GLOBAL_APP_CONFIG.MST_CLIENT WHERE ID = p_client_id; 
 
    EXCEPTION WHEN OTHERS THEN 
 
        v_from_user := 'contactus@techriskpartners.com'; 
 
    END; 
 
 
    for i in ( 
            select column_value as user_id from table(apex_string.split(v_to_users, ',')) 
        ) loop 
 
            begin 
 
                v_user_id := TO_NUMBER(i.user_id); 
                 
                BEGIN 
 
                    SELECT UPPER(EMAIL) INTO v_user_mail FROM IRM_GLOBAL_APP_CONFIG.MST_USERS 
                    WHERE ID = v_user_id; 
 
                exception when OTHERS then 
 
                    v_user_mail := NULL; 
 
                END; 
 
                IF v_user_mail IS NOT NULL THEN 
 
                    v_to_user_mails := v_to_user_mails || ',' || v_user_mail; 
 
                END IF; 
 
            exception when VALUE_ERROR then

                IF REGEXP_LIKE(i.user_id, '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$') THEN
 
                    v_to_user_mails := v_to_user_mails || ',' || upper(i.user_id);

                END IF;
 
            end; 
    end loop; 
     
    for j in ( 
            select column_value as user_id from table(apex_string.split(v_cc_users, ',')) 
        ) loop 
 
            begin 
 
                v_user_id := TO_NUMBER(j.user_id); 
                 
                BEGIN 
 
                    SELECT UPPER(EMAIL) INTO v_user_mail FROM IRM_GLOBAL_APP_CONFIG.MST_USERS 
                    WHERE ID = v_user_id; 
 
                exception when OTHERS then 
 
                    v_user_mail := NULL; 
 
                END; 
 
                IF v_user_mail IS NOT NULL THEN 
 
                    v_cc_user_mails := v_cc_user_mails || ',' || v_user_mail; 
 
                END IF; 
 
            exception when VALUE_ERROR then

                IF REGEXP_LIKE(j.user_id, '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$') THEN
 
                    v_cc_user_mails := v_cc_user_mails || ',' || upper(j.user_id); 

                END IF;
            end; 
    end loop; 
 
    v_to_user_mails := TRIM(BOTH ',' FROM v_to_user_mails); 
    v_cc_user_mails := TRIM(BOTH ',' FROM v_cc_user_mails); 
 
    v_response := v_response || ', TO USERS MAILS : ' || v_to_user_mails || ', CC USERS USERS : ' || v_cc_user_mails; 
 
 
 
    IF UPPER(p_mail_type) = 'SINGLE' THEN 
 
        for k in ( 
            select column_value AS user_mail from table(apex_string.split(v_to_user_mails, ',')) 
        ) loop 
 
            BEGIN 
 
                SELECT FIRST_NAME  
                    INTO v_first_name  
                FROM IRM_GLOBAL_APP_CONFIG.MST_USERS  
                WHERE  
                    IS_ACTIVE = 'Y'  
                    AND UPPER(EMAIL) = UPPER(k.user_mail); 
            EXCEPTION WHEN OTHERS THEN 
                v_first_name := 'User'; 
            END; 
 
            v_body := REPLACE(p_body, '#F_NAME#', v_first_name); 
 
            APEX_MAIL.SEND( 
                p_to        => k.user_mail, 
                p_from      => v_from_user, 
                p_cc        => v_cc_user_mails, 
                p_subj      => p_subject, 
                p_body      => v_body, 
                p_body_html => v_body 
            ); 
 
            INSERT INTO IRM_GLOBAL_APP_CONFIG.LOG_EMAIL ( 
                FROM_USER, 
                TO_USERS, 
                CC_USERS, 
                SUBJECT, 
                BODY 
 
            ) VALUES ( 
                v_from_user, 
                k.user_mail, 
                v_cc_user_mails, 
                p_subject, 
                p_body 
 
            ); 
 
 
 
        end loop; 
 
    ELSE 
 
         
        APEX_MAIL.SEND( 
            p_to        => v_to_users, 
            p_from      => v_from_user, 
            p_cc        => v_cc_user_mails, 
            p_subj      => p_subject, 
            p_body      => p_body, 
            p_body_html => p_body 
        );
 
     
        INSERT INTO IRM_GLOBAL_APP_CONFIG.LOG_EMAIL ( 
            FROM_USER, 
            TO_USERS, 
            CC_USERS, 
            SUBJECT, 
            BODY 
 
        ) VALUES ( 
            v_from_user, 
            v_to_users, 
            v_cc_user_mails, 
            p_subject, 
            p_body 
 
        ); 
 
 
 
    END IF; 

end "SP_SEND_MAIL_V1";
/
create or replace PROCEDURE SP_SOD_RESULT_SAVE_V2 --USING
(
    v_schema_name IN VARCHAR2 DEFAULT 'IRM_SA_ACCESS',
    p_request_id IN NUMBER
) AS 
    l_url           VARCHAR2(1000); 
    l_username      VARCHAR2(100); 
    l_password      VARCHAR2(100);
    v_auth_type      VARCHAR2(100);
    l_response_clob CLOB; 
    v_jwt_token CLOB; 
    l_total_results NUMBER;


    v_profile_id number;
    v_ormc_id number;

BEGIN 
    EXECUTE IMMEDIATE
    'SELECT RMC_RESULT_ID, PROFILE_ID FROM TRN_SIMULATION_JOBS WHERE ID = :p_id
    ' INTO v_ormc_id, v_profile_id USING p_request_id;

    SELECT ERP_URL, AUTH_TYPE 
    INTO l_url, v_auth_type
    FROM IRM_GLOBAL_APP_CONFIG.MST_CLIENT_ERP_CONFIG 
    WHERE id = v_profile_id;

    -- Step 2: Set request headers 
    apex_web_service.g_request_headers(1).name  := 'Content-Type'; 
    apex_web_service.g_request_headers(1).value := 'application/vnd.oracle.adf.action+json'; 


    if v_auth_type = 'JWT' then

        v_jwt_token := IRM_GLOBAL_APP_CONFIG.FN_GENERATE_JWT_TOKEN_V1(v_profile_id);

        apex_web_service.g_request_headers(2).name := 'Authorization';
        apex_web_service.g_request_headers(2).value := 'Bearer ' || v_jwt_token;


        -- Step 3: Fetch the total number of results 
        l_response_clob := apex_web_service.make_rest_request( 
            p_url         => l_url || '/fscmRestApi/resources/11.13.18.05/advancedControlsRolesProvisioning?finder=getUserProvisioningAnalysisIncidents;requestId=' || v_ormc_id || '&onlyData=true&totalResults=true&limit=1', 
            p_http_method => 'GET'
        ); 


    ELSE
        -- Step 1: Retrieve credentials and base URL 
        SELECT ERP_USERNAME, ERP_PASSWORD
            INTO l_username, l_password
        FROM IRM_GLOBAL_APP_CONFIG.MST_CLIENT_ERP_CONFIG WHERE id = v_profile_id;

        -- Step 3: Fetch the total number of results 
        l_response_clob := apex_web_service.make_rest_request( 
            p_url         => l_url || '/fscmRestApi/resources/11.13.18.05/advancedControlsRolesProvisioning?finder=getUserProvisioningAnalysisIncidents;requestId=' || v_ormc_id || '&onlyData=true&totalResults=true&limit=1', 
            p_http_method => 'GET', 
            p_username    => l_username, 
            p_password    => l_password 
        );

    end if;

 
 
    -- Step 4: Parse JSON response and extract total results 
    apex_json.parse(l_response_clob); 
    l_total_results := apex_json.get_number('totalResults'); 
 
    IF l_total_results > 0 THEN 


        if v_auth_type = 'JWT' then

            v_jwt_token := IRM_GLOBAL_APP_CONFIG.FN_GENERATE_JWT_TOKEN_V1(v_profile_id);

            apex_web_service.g_request_headers(2).name := 'Authorization';
            apex_web_service.g_request_headers(2).value := 'Bearer ' || v_jwt_token;

            l_response_clob := apex_web_service.make_rest_request( 
                p_url         => l_url || '/fscmRestApi/resources/11.13.18.05/advancedControlsRolesProvisioning?finder=getUserProvisioningAnalysisIncidents;requestId=' || v_ormc_id || '&onlyData=true&totalResults=true&limit=' || l_total_results, 
                p_http_method => 'GET'
            ); 
        
        else

            l_response_clob := apex_web_service.make_rest_request( 
                p_url         => l_url || '/fscmRestApi/resources/11.13.18.05/advancedControlsRolesProvisioning?finder=getUserProvisioningAnalysisIncidents;requestId=' || v_ormc_id || '&onlyData=true&totalResults=true&limit=' || l_total_results, 
                p_http_method => 'GET', 
                p_username    => l_username, 
                p_password    => l_password 
            ); 
        end if;

        -- Parse JSON response 
        apex_json.parse(l_response_clob); 
 
        -- Step 5: Insert records into TRN_SOD_REPORT 
        FOR i IN 1 .. apex_json.get_count('items') LOOP 
            EXECUTE IMMEDIATE 'INSERT INTO ' || v_schema_name || '.TRN_SOD_REPORT ( 
                CONTROL_ID, 
                CONTROL_NAME, 
                INPUT_ROLE_CODE, 
                INPUT_ROLE_NAME, 
                INCIDENT_PATH_CODE, 
                INCIDENT_PATH, 
                CONFLICTING_ROLE, 
                RESULT_ID 
            ) VALUES ( 
                :control_id, 
                :control_name, 
                :input_role_code, 
                :input_role_name, 
                :incident_path_code, 
                :incident_path, 
                :conflicting_role, 
                :result_id 
            )' USING  
                apex_json.get_number('items[%d].controlId', i), 
                apex_json.get_varchar2('items[%d].controlName', i), 
                apex_json.get_varchar2('items[%d].inputRoleCode', i), 
                apex_json.get_varchar2('items[%d].inputRoleName', i), 
                apex_json.get_varchar2('items[%d].incidentPathCode', i), 
                apex_json.get_varchar2('items[%d].incidentPath', i), 
                apex_json.get_varchar2('items[%d].conflictingRole', i), 
                p_request_id; 
        END LOOP; 
 
        COMMIT; 

    ELSE 
        DBMS_OUTPUT.PUT_LINE('SOMETHING SOMETHING'); 
 
    END IF; 
 
    -- Step 6: Update TRN_SIMULATION_JOBS 
    EXECUTE IMMEDIATE 'UPDATE ' || v_schema_name || '.TRN_SIMULATION_JOBS  
                       SET REPORT_GENERATED = ''Y''  
                       WHERE ID = :p_request_id' USING p_request_id; 
     
    COMMIT; 
EXCEPTION 
    WHEN OTHERS THEN 
        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM); 
        ROLLBACK; 
END SP_SOD_RESULT_SAVE_V2;
/
create or replace PROCEDURE SP_SYNC_EXTRACT_FILES_EBS( 
    p_sync_header_id IN NUMBER, 
    p_cust_id IN NUMBER, 
    p_schema_name VARCHAR2 
) 
IS 
    -- Define a record type to hold both file_name and file_blob 
    TYPE file_record IS RECORD ( 
        file_name VARCHAR2(4000), 
        file_blob BLOB, 
        ID NUMBER 
    ); 
    -- Define a collection type to hold multiple records 
    TYPE file_record_table IS TABLE OF file_record; 
    -- Declare variables 
    v_file_data file_record_table; 
    -- v_schema_name VARCHAR2(1000);  -- Replace with the desired schema name 
    v_error_msg varchar2(4000); 
 
    -- to store datasource id using sync_header_id  
    v_datasource_id NUMBER; 
 
BEGIN 
    -- inserting in log table 
    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('File extract started!', 2, p_sync_header_id); 
    -- ends 
    COMMIT; 
 
    BEGIN 
        -- Collect file names and blobs into the collection dynamically from the specified schema 
        EXECUTE IMMEDIATE ' 
            SELECT file_name, file_blob, ID 
            FROM ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES WHERE SYNC_HEADER_ID = :p_sync_header_id' 
        BULK COLLECT INTO v_file_data USING p_sync_header_id; 
    EXCEPTION  
    WHEN NO_DATA_FOUND 
        THEN  
            v_error_msg := 'No file found against the zip file. Error : ' || SQLERRM; 
 
            INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
            VALUES(v_error_msg, 2, p_sync_header_id); 
 
            COMMIT; 
    WHEN OTHERS 
        THEN  
            v_error_msg := 'Error in getting Data : ' || SQLERRM; 
 
            INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
            VALUES(v_error_msg, 2, p_sync_header_id); 
 
            COMMIT; 
    END; 
 
    BEGIN 
        -- Collect datasource id for the perticular sync header id 
        EXECUTE IMMEDIATE ' 
            SELECT DATASOURCE_ID 
            FROM ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES WHERE SYNC_HEADER_ID = :p_sync_header_id' 
        INTO v_datasource_id USING p_sync_header_id; 
    EXCEPTION  
    WHEN NO_DATA_FOUND 
        THEN  
            v_error_msg := 'No data found against the sync header id. Error : ' || SQLERRM; 
 
            INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
            VALUES(v_error_msg, 2, p_sync_header_id); 
 
            COMMIT; 
    WHEN OTHERS 
        THEN  
            v_error_msg := 'Error in getting Datasource id : ' || SQLERRM; 
 
            INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
            VALUES(v_error_msg, 2, p_sync_header_id); 
 
            COMMIT; 
    END; 
 
    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Data Loading Started'' WHERE ID = :ID' USING p_sync_header_id; 
 
    -- Loop through the collected file names 
    FOR i IN 1..v_file_data.COUNT  
    LOOP 
                -- inserting in log table 
        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Inserting for file ' || v_file_data(i).file_name, 2, p_sync_header_id); 
        -- ends 
        COMMIT; 
            -- Insert data into SAMPLE_TABLE based on parsed content, using the schema dynamically 
            IF LOWER(v_file_data(i).file_name) ='menus.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                    'INSERT INTO ' || p_schema_name || '.XX_EBS_SOD_MENUS (MENU_ID, MENU_NAME, MENU_TYPE, USER_MENU_NAME, IRM_CUST_ID, IRM_JOB_ID)  
                    SELECT COL001, COL002, COL003, COL004, :P0_CUST_ID, :P9_ID 
                    FROM TABLE( 
                        APEX_DATA_PARSER.parse( 
                            p_content   => :file_blob, 
                            p_file_name => :file_name 
                        ) 
                    ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id,v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for menus: ' || v_file_data(i).file_name, 2,p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS 
                    THEN  
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occured in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
 
            ELSIF LOWER(v_file_data(i).file_name) ='menu_entries.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_SOD_MENU_ENTRIES(MENU_ID, ENTRY_SEQ, SUB_MENU_ID, FN_ID, GRANT_FLAG, PROMPT, DESCRIPT,IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, COL004, COL005, COL006, COL007, :P0_CUST_ID, :P9_ID 
                    FROM TABLE( 
                        APEX_DATA_PARSER.parse( 
                            p_content   => :file_blob, 
                            p_file_name => :file_name 
                        ) 
                    ) OFFSET 1 ROWS' 
                    USING p_cust_id,p_sync_header_id,v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for menu_entries: ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS 
                    THEN  
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occured in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
 
            ELSIF LOWER(v_file_data(i).file_name) ='functions.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_SOD_FUNCTIONS(FN_ID, FN_NAME, FN_TYPE, USER_FN_NAME,IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, COL004, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id,p_sync_header_id,v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for functions: ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS 
                    THEN  
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2,p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occured in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
 
            ELSIF LOWER(v_file_data(i).file_name) ='responsibilities.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_SOD_RESPONSIBILITIES(APP_ID, RESP_ID, RESP_NAME, RESP_KEY, OU_ID, SECURITY_POLICY_ID, SECURITY_POLICY, LEDGER, DATA_ACCESS_SET, MENU_ID, DATA_GROUP_ID,IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, COL004, COL005, COL006, COL007, COL008, COL009, COL010, COL011, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING  p_cust_id,p_sync_header_id,v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for responsibilities: ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS 
                    THEN  
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occured in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
 
            ELSIF LOWER(v_file_data(i).file_name) ='resp_exclusions.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_SOD_RESP_EXCLUSIONS(APP_ID, RESP_ID, ACTION_ID, RULE_TYPE,IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, COL004, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id,p_sync_header_id,v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for functions: ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS 
                    THEN  
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2,p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occured in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
 
            ELSIF LOWER(v_file_data(i).file_name) = 'users.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_SOD_USERS (USER_ID, USERNAME, FIRSTNAME, LASTNAME, IRM_JOB_ID, IRM_CUST_ID)  
                        SELECT COL001, COL002, COL003, COL004, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_sync_header_id, p_cust_id,v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for users: ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS 
                    THEN  
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occured in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
 
            ELSIF LOWER(v_file_data(i).file_name) = 'user_resp.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_SOD_USER_RESP (USER_ID, RESP_ID, APP_ID, IRM_CUST_ID, IRM_JOB_ID)  
                         SELECT COL001, COL002, COL003,:P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id,v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for user_resp: ' || v_file_data(i).file_name, 2,p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS 
                    THEN  
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2,p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occured in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'ap_bank_accounts_all.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_AP_BANK_ACCOUNTS_ALL (LAST_UPDATE_DATE, CREATED_BY, BANK_ACCOUNT_NAME,BANK_ACCOUNT_NUM, 
                        BANK_ACCOUNT_TYPE,MIN_CHECK_AMOUNT,MAX_CHECK_AMOUNT,CURRENCY_CODE,LAST_UPDATED_BY,CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                            SELECT COL001, COL002, COL003,COL004,COL005,COL006,COL007,COL008,COL009,C0L010,:P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id,v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for ap_bank_accounts_all : ' || v_file_data(i).file_name, 2,p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS 
                    THEN  
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2,p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occured in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'ap_bank_branches.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_AP_BANK_BRANCHES (BANK_NAME, LAST_UPDATED_BY, CREATED_BY,BANK_BRANCH_ID,LAST_UPDATE_DATE, 
                        BANK_BRANCH_NAME,DESCRIPTION,CONTACT_PREFIX,CONTACT_TITLE,BANK_NUM,LAST_UPDATE_LOGIN, CREATION_DATE,INSTITUTION_TYPE,CLEARING_HOUSE_ID, 
                        PAYROLL_BANK_ACCOUNT_ID,RFC_IDENTIFIER,BANK_ADMIN_EMAIL,IRM_CUST_ID, IRM_JOB_ID)  
                            SELECT COL001, COL002, COL003,COL004,COL005,COL006,COL007,COL008,COL009,C0L010,COL011,COL012,COL013,COL014,COL014,COL015,COL016,COL017,:P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id,v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for ap_bank_branches : ' || v_file_data(i).file_name, 2,p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS 
                    THEN  
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2,p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occured in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'ap_checks_all.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_AP_CHECKS_ALL (CHECK_ID, CHECK_NUMBER, CREATION_DATE,IRM_CUST_ID, IRM_JOB_ID)  
                            SELECT COL001, COL002, COL003,:P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id,v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for ap_checks_all : ' || v_file_data(i).file_name, 2,p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS 
                    THEN  
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2,p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occured in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'ap_inv_aprvl_hist_all.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_AP_INV_APRVL_HIST_ALL (INVOICE_ID, RESPONSE, LAST_UPDATED_BY,CREATION_DATE,IRM_CUST_ID, IRM_JOB_ID)  
                            SELECT COL001, COL002, COL003,COL004,:P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id,v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for ap_inv_aprvl_hist_all : ' || v_file_data(i).file_name, 2,p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS 
                    THEN  
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2,p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occured in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'ap_invoice_distributions_all.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_AP_INVOICE_DISTRIBUTIONS_ALL (INVOICE_ID, INVOICE_LINE_NUMBER, DIST_CODE_COMBINATION_ID,CREATION_DATE,IRM_CUST_ID, IRM_JOB_ID)  
                            SELECT COL001, COL002, COL003,COL004,:P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id,v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for ap_invoice_distributions_all : ' || v_file_data(i).file_name, 2,p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS 
                    THEN  
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2,p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occured in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'ap_invoice_lines_all.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_AP_INVOICE_LINES_ALL (INVOICE_ID, LINE_NUMBER, LINE_TYPE_LOOKUP_CODE,LINE_AMOUNT,CREATED_BY, 
                        LAST_UPDATED_BY,CREATION_DATE,IRM_CUST_ID, IRM_JOB_ID)  
                            SELECT COL001, COL002, COL003,COL004,COL005,COL006,COL007,:P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id,v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for ap_invoice_lines_all : ' || v_file_data(i).file_name, 2,p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS 
                    THEN  
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2,p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occured in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'ap_invoice_payments_all.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_AP_INVOICE_PAYMENTS_ALL (INVOICE_ID, CHECK_ID, AMOUNT,INVOICE_PAYMENT_TYPE,CREATION_DATE,IRM_CUST_ID, IRM_JOB_ID)  
                            SELECT COL001, COL002, COL003,COL004,COL005,:P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id,v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for ap_invoice_payments_all : ' || v_file_data(i).file_name, 2,p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS 
                    THEN  
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2,p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occured in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'ap_invoices_all.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_AP_INVOICES_ALL  
                        (INVOICE_ID, INVOICE_NUM, INVOICE_CURRENCY_CODE, PAYMENT_STATUS_FLAG, INVOICE_TYPE_LOOKUP_CODE,INVOICE_DATE,VENDOR_ID,VENDOR_SITE_ID,INVOICE_AMOUNT, 
                        TERMS_ID,PO_HEADER_ID,CREATION_DATE,LAST_UPDATE_DATE,LAST_UPDATED_BY,CREATED_BY,ORG_ID,SET_OF_BOOKS_ID, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, COL004, COL005,COL006,COL007,COL008,COL009,COL010,COL011,COL012,COL013,COL014,COL015,COL016,COL017, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for ap_invoices_all : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'ap_payment_history_all.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_AP_PAYMENT_HISTORY_ALL  
                        (LAST_UPDATED_BY, CREATED_BY, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for ap_payment_history_all : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'ap_payment_schedules_all.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_AP_PAYMENT_SCHEDULES_ALL  
                        (INVOICE_ID, AMOUNT_REMAINING, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003,:P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for ap_payment_schedules_all : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'ap_supplier_sites_all.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_AP_SUPPLIER_SITES_ALL  
                        (VENDOR_ID, VENDOR_SITE_ID, VENDOR_SITE_CODE, EMAIL_ADDRESS, ORG_ID,LAST_UPDATED_BY,PURCHASING_SITE_FLAG,CREATED_BY,INACTIVE_DATE, 
                        CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, COL004, COL005, COL006, COL007, COL008, COL009, COL010, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for ap_supplier_sites_all : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'ap_suppliers.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_AP_SUPPLIERS  
                        (VENDOR_ID, END_DATE_ACTIVE, LAST_UPDATED_BY, CREATED_BY, VENDOR_NAME, SEGMENT1, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, COL004, COL005, COL006, COL007, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for ap_suppliers : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'ap_system_parameters_all.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_AP_SYSTEM_PARAMETERS_ALL  
                        (LAST_UPDATED_BY, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001,:P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for ap_system_parameters_all : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
                     
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'ap_terms.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_AP_TERMS  
                        (TERM_ID, NAME, CREATED_BY, LAST_UPDATED_BY, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for ap_terms : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
                     
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'ap_wfapproval_history_v.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_AP_WORKFLOW_APPROVAL_HISTORY_V  
                        (APPROVER_NAME, INVOICE_ID, RESPONSE, LAST_UPDATE_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, COL004,:P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for ap_workflow_approval_history_v : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID'  
                    USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'applications.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_APPLICATIONS  
                        (APP_ID, APP_NAME, APP_SHORT_NAME, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003,:P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for applications : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'ar_cash_receipt_history_all.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_AR_CASH_RECEIPT_HISTORY_ALL  
                        (CASH_RECEIPT_ID, CASH_RECEIPT_HISTORY_ID, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003,:P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for ar_cash_receipt_history_all : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'ar_cash_receipts_all.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_AR_CASH_RECEIPTS_ALL  
                        (RECEIPT_NUMBER, CASH_RECEIPT_ID, RECEIPT_DATE, AMOUNT, CREATED_BY,LAST_UPDATED_BY,CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, COL004, COL005,COL006,COL007,:P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for ar_cash_receipts_all : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'ar_receipt_classes.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_AR_RECEIPT_CLASSES  
                        (LAST_UPDATED_BY, CREATED_BY, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003,:P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for ar_receipt_classes : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'ar_receipt_methods.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_AR_RECEIPT_METHODS  
                        (LAST_UPDATED_BY, CREATED_BY, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003,:P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for ar_receipt_methods : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'ar_receivable_applications_all.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_AR_RECEIVABLE_APPLICATIONS_ALL  
                        (CASH_RECEIPT_HISTORY_ID, CASH_RECEIPT_ID, DISPLAY, APPLIED_CUSTOMER_TRX_ID, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, COL004, COL005, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for ar_receivable_applications_all : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'ben_elig_per_f.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_BEN_ELIG_PER_F  
                        (PERSON_ID, EFFECTIVE_START_DATE, EFFECTIVE_END_DATE, CREATED_BY,LAST_UPDATED_BY,CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, COL004, COL005, COL006, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for ben_elig_per_f : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'ben_ler_f.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_BEN_LER_F  
                        (LAST_UPDATED_BY, CREATED_BY, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003,:P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for ben_ler_f : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'ben_per_in_ler.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_BEN_PER_IN_LER  
                        (PERSON_ID,  CREATED_BY,LAST_UPDATED_BY, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, COL004, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for ben_per_in_ler : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'ben_pgm_f.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_BEN_PGM_F  
                        (LAST_UPDATED_BY, CREATED_BY, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for ben_pgm_f : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'conc_programs.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_CONC_PROGRAMS  
                        (APP_ID, CONC_PROG_ID, CONC_PROG_NAME, USER_CONC_PROG, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, COL004, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for conc_programs : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'datagroups.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_DATAGROUPS  
                        (DATAGROUP_ID, DATAGROUP_NAME,IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for datagroups : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'fa_additions.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_FA_ADDITIONS  
                        (LAST_UPDATED_BY, CREATED_BY, ASSET_ID, DESCRIPTION, CREATION_DATE,ASSET_NUMBER,TAG_NUMBER,LAST_UPDATE_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, COL004, COL005,COL006,COL007,COL008, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for fa_additions : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'fa_bonus_rules.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_FA_BONUS_RULES  
                        (CREATION_DATE, LAST_UPDATE_DATE, LAST_UPDATED_BY, CREATED_BY, BONUS_RULE, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, COL004, COL005, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for fa_bonus_rules : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'fa_book_controls.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_FA_BOOK_CONTROLS  
                        (BOOK_TYPE_CODE, BOOK_TYPE_NAME, DEPRN_CALENDAR, BOOK_CLASS, SET_OF_BOOKS_ID, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, COL004, COL005,COL006, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for fa_book_controls : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'fa_books.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_FA_BOOKS  
                        (LAST_UPDATED_BY, BOOK_TYPE_CODE, ORIGINAL_COST, SALVAGE_VALUE, DATE_PLACED_IN_SERVICE,DATE_EFFECTIVE,DEPRN_START_DATE,DEPRN_METHOD_CODE, 
                        LIFE_IN_MONTHS,RATE_ADJUSTMENT_FACTOR,SALVAGE_TYPE,PRORATE_CONVENTION_CODE,PRORATE_DATE,CAPITALIZE_FLAG,RETIREMENT_PENDING_FLAG,DEPRECIATE_FLAG, 
                        PERIOD_COUNTER_FULLY_RETIRED,ASSET_ID,DATE_INEFFECTIVE,IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, COL004, COL005,COL006,COL007,COL008,COL009,COL010,COL011,COL012,COL013,COL014,COL015,COL016,COL017,COL018,COL019,:P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for fa_books : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'fa_calendar_types.csv' THEN ----  DESCRIPTION, CALENDAR_TYPE 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_FA_CALENDAR_TYPES  
                        (LAST_UPDATED_BY, CREATED_BY, DESCRIPTION, CALENDAR_TYPE, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for fa_calendar_types : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'fa_ceiling_types.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_FA_CEILING_TYPES  
                        (LAST_UPDATED_BY, CREATED_BY, CREATION_DATE, CEILING_TYPE, CEILING_NAME, CURRENCY_CODE, DESCRIPTION, LAST_UPDATE_DATE,LAST_UPDATE_LOGIN, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, COL004, COL005,COL006,COL007,COL008,COL009,:P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for fa_ceiling_types : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'fa_convention_types.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_FA_CONVENTION_TYPES  
                        (DESCRIPTION, PRORATE_CONVENTION_CODE,CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for fa_convention_types : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'fa_deprn_events.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_FA_DEPRN_EVENTS  
                        (LAST_UPDATED_BY, CREATED_BY, ASSET_ID, BOOK_TYPE_CODE, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, COL004, COL005, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for fa_deprn_events : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'fa_flat_rates.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_FA_FLAT_RATES  
                        (LAST_UPDATED_BY, CREATED_BY, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for fa_flat_rates : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'fa_itc_rates.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_FA_ITC_RATES  
                        (LAST_UPDATED_BY, CREATED_BY,CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003,:P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for fa_itc_rates : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END;  
            ELSIF LOWER(v_file_data(i).file_name) = 'fa_itc_recapture_rates.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_FA_ITC_RECAPTURE_RATES  
                        (LAST_UPDATE_DATE, LAST_UPDATED_BY, CREATED_BY, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, COL004,:P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for fa_itc_recapture_rates : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'fa_lookups_tl.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_FA_LOOKUPS_TL  
                        (LOOKUP_TYPE, LANGUAGE, LOOKUP_CODE, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, COL004, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for fa_lookups_tl : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'fa_maint_events.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_FA_MAINT_EVENTS  
                        (LAST_UPDATE_DATE, LAST_UPDATED_BY, CREATED_BY, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, COL004, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for fa_maint_events : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'fa_maint_schedule_dtl.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_FA_MAINT_SCHEDULE_DTL  
                        (LAST_UPDATE_DATE, LAST_UPDATED_BY, CREATED_BY, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, COL004, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for fa_maint_schedule_dtl : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'fa_maint_schedule_hdr.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_FA_MAINT_SCHEDULE_HDR  
                        (LAST_UPDATE_DATE, LAST_UPDATED_BY, CREATED_BY, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, COL004,:P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for fa_maint_schedule_hdr : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'fa_methods.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_FA_METHODS  
                        (METHOD_CODE, NAME, CREATED_BY, LAST_UPDATED_BY, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, COL004, COL005, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for fa_methods : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'fa_retirements.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_FA_RETIREMENTS  
                        (LAST_UPDATED_BY,CREATED_BY,CREATION_DATE,RETIREMENT_ID, RETIREMENT_TYPE_CODE,ASSET_ID, BOOK_TYPE_CODE, DATE_RETIRED,DATE_EFFECTIVE,COST_RETIRED, 
                        STATUS,RETIREMENT_PRORATE_CONVENTION,COST_OF_REMOVAL,NBV_RETIRED,PROCEEDS_OF_SALE,IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, COL004, COL005,COL006,COL006,COL007,COL008,COL009,COL010,COL011,COL012,COL013,COL014,COL015, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for fa_retirements : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'fa_super_groups.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_FA_SUPER_GROUPS  
                        (LAST_UPDATE_DATE, LAST_UPDATED_BY, CREATED_BY, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, COL004, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID)  
                    VALUES('Insertion completed for fa_super_groups : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'financials_system_params_all.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_FINANCIALS_SYSTEM_PARAMS_ALL  
                        (LAST_UPDATED_BY, CREATED_BY, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003,:P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for financials_system_params_all : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'fnd_territories.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_FND_TERRITORIES  
                        (NLS_TERRITORY, TERRITORY_CODE, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for fnd_territories : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'fnd_user.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_FND_USER  
                        (USER_ID, USER_NAME, EMPLOYEE_ID, LAST_UPDATE_DATE, LAST_UPDATED_BY, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, COL004, COL005, COL006, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for fnd_user : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'gl_automatic_posting_sets.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_GL_AUTOMATIC_POSTING_SETS  
                        (LAST_UPDATED_BY, CREATED_BY, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003,:P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for gl_automatic_posting_sets : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'gl_autorev_criteria_sets.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_GL_AUTOREV_CRITERIA_SETS  
                        (LAST_UPDATED_BY, CREATED_BY, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003,:P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for gl_autorev_criteria_sets : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'gl_code_combinations.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_GL_CODE_COMBINATIONS  
                        (LAST_UPDATED_BY, CODE_COMBINATION_ID, LAST_UPDATE_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for gl_code_combinations : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'gl_code_combinations_kfv.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_GL_CODE_COMBINATIONS_KFV  
                        (CODE_COMBINATION_ID, CONCATENATED_SEGMENTS, LAST_UPDATE_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for gl_code_combinations_kfv : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'gl_currencies.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_GL_CURRENCIES  
                        (LAST_UPDATED_BY, CREATED_BY, CREATION_DATE,IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003,:P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for gl_currencies : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'gl_daily_rates.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_GL_DAILY_RATES  
                        (LAST_UPDATED_BY, CREATED_BY, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for gl_daily_rates : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'gl_encumbrance_types.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_GL_ENCUMBRANCE_TYPES  
                        (LAST_UPDATED_BY, CREATED_BY, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for gl_encumbrance_types : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'gl_iea_transaction_types.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_GL_IEA_TRANSACTION_TYPES  
                        (LAST_UPDATED_BY, CREATED_BY, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003,:P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    -- Log successful insertion 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for gl_iea_transaction_types : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    -- Mark the file as inserted 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                     
                EXCEPTION WHEN OTHERS  
                    THEN 
                    -- Capture error details 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    -- Update sync header with error status 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'gl_import_references.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_GL_IMPORT_REFERENCES  
                        (LAST_UPDATED_BY, CREATED_BY, JE_HEADER_ID, JE_LINE_NUM, GL_SL_LINK_TABLE, GL_SL_LINK_ID, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, COL004, COL005, COL006,COL007, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for gl_import_references : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                     
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'gl_je_categories.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_GL_JE_CATEGORIES  
                        (LAST_UPDATED_BY, CREATED_BY, CREATION_DATE,ROW_ID, JE_CATEGORY_NAME, LANGUAGE, SOURCE_LANG, USER_JE_CATEGORY_NAME, JE_CATEGORY_KEY, LAST_UPDATE_DATE, 
                        LAST_UPDATE_LOGIN, DESCRIPTION, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, COL004, COL005,COL006,COL007,COL008,COL009,COL010,COL011,COL012, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for gl_je_categories : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                     
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID'  USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'gl_je_headers.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_GL_JE_HEADERS  
                        (CREATED_BY,NAME,DESCRIPTION,JE_SOURCE,JE_CATEGORY,PERIOD_NAME,CURRENCY_CODE,STATUS,LAST_UPDATED_BY,POSTED_DATE,JE_HEADER_ID,CREATION_DATE, 
                        RUNNING_TOTAL_ACCOUNTED_DR,ACTUAL_FLAG, LEDGER_ID, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, COL004, COL005,COL006,COL007,COL008,COL009,COL010,COL011,COL012,COL013,COL014,COL015, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for gl_je_headers : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                     
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'gl_je_lines.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_GL_JE_LINES  
                        (LAST_UPDATED_BY, CREATED_BY,JE_HEADER_ID, JE_LINE_NUM, DESCRIPTION, CODE_COMBINATION_ID,CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, COL004, COL005,COL006,COL007, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for gl_je_lines : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                     
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'gl_je_sources.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_GL_JE_SOURCES  
                        (LAST_UPDATED_BY, CREATED_BY, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for gl_je_sources : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                     
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'gl_ledgers.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_GL_LEDGERS  
                        (LAST_UPDATED_BY,CREATED_BY,LEDGER_ID,NAME, PERIOD_SET_NAME, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, COL004, COL005,COL006, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for gl_ledgers : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                     
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'gl_period_sets.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_GL_PERIOD_SETS  
                        (LAST_UPDATED_BY, CREATED_BY, CREATION_DATE, PERIOD_SET_NAME, LAST_UPDATE_LOGIN, DESCRIPTION, ZD_EDITION_NAME, ZD_SYNC, LAST_UPDATE_DATE, 
                        SECURITY_FLAG, PERIOD_SET_ID, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, COL004, COL005, COL006,COL007,COL008,COL009,COL010,COL011, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for gl_period_sets : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'gl_period_statuses.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_GL_PERIOD_STATUSES  
                        (CLOSING_STATUS, SET_OF_BOOKS_ID, APPLICATION_ID, LAST_UPDATED_BY, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, COL004, COL005, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for gl_period_statuses : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'gl_period_types.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_gl_period_typesS  
                        (LAST_UPDATED_BY, CREATED_BY, LAST_UPDATE_DATE, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, COL004, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for gl_period_types : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'gl_periods.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_GL_PERIODS  
                        (PERIOD_SET_NAME, LAST_UPDATED_BY, CREATION_DATE, PERIOD_NAME, CREATED_BY, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, COL004, COL005, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for gl_periods : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'gl_recurring_batches.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_GL_RECURRING_BATCHES  
                        (LAST_UPDATED_BY, CREATED_BY, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for gl_recurring_batches : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'gl_recurring_headers.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_GL_RECURRING_HEADERS  
                        (LAST_UPDATED_BY, CREATED_BY, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for gl_recurring_headers : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'gl_recurring_lines.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_GL_RECURRING_LINES  
                        (LAST_UPDATED_BY, CREATED_BY, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for gl_recurring_lines : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'gl_sets_of_books.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_GL_SETS_OF_BOOKS  
                        (LAST_UPDATED_BY, CREATED_BY, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for gl_sets_of_books : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'hr_all_organization_units.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_HR_ALL_ORGANIZATION_UNITS  
                        (LAST_UPDATE_DATE, LAST_UPDATED_BY, CREATED_BY, CREATION_DATE, ORGANIZATION_ID, NAME, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, COL004, COL005, COL006, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for hr_all_organization_units : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'hr_assignment_sets.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_HR_ASSIGNMENT_SETS  
                        (LAST_UPDATED_BY, CREATED_BY, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for hr_assignment_sets : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'hr_locations_all.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_HR_LOCATIONS_ALL  
                        (LOCATION_CODE, LOCATION_ID, TOWN_OR_CITY, REGION_1, COUNTRY, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, COL004, COL005, COL006, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for hr_locations_all : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'hr_operating_units.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_HR_OPERATING_UNITS  
                        (ORGANIZATION_ID, NAME, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for hr_operating_units : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'hr_all_organization_units_tl.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_HR_ALL_ORGANIZATION_UNITS_TL  
                        (NAME, ORGANIZATION_ID, LANGUAGE, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, COL004, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for hr_all_organization_units_tl : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'hz_cust_acct_sites_all.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_HZ_CUST_ACCT_SITES_ALL  
                        (LAST_UPDATED_BY, CREATED_BY, CREATION_DATE, CUST_ACCT_SITE_ID, CUST_ACCOUNT_ID, PARTY_SITE_ID, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, COL004, COL005, COL006, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for hz_cust_acct_sites_all : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'hz_cust_accounts.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_HZ_CUST_ACCOUNTS  
                        (LAST_UPDATED_BY, CREATED_BY, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for hz_cust_accounts : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'hz_cust_site_uses_all.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_HZ_CUST_SITE_USES_ALL  
                        (SITE_USE_ID, CUST_ACCT_SITE_ID, SITE_USE_CODE, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, COL004, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for hz_cust_site_uses_all : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'hz_locations.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_HZ_LOCATIONS  
                        (CITY, STATE, COUNTRY, LOCATION_ID, ADDRESS1, ADDRESS2, ADDRESS3, LAST_UPDATED_BY, CREATED_BY, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, COL004, COL005, COL006, COL007, COL008, COL009, COL010, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for hz_locations : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'hz_parties.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_HZ_PARTIES  
                        (PARTY_NUMBER, PARTY_NAME, PARTY_ID, LAST_UPDATED_BY, CREATED_BY, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, COL004, COL005, COL006, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for hz_parties : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'hz_party_sites.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_HZ_PARTY_SITES  
                        (PARTY_SITE_NUMBER, PARTY_SITE_ID, LOCATION_ID, PARTY_ID, LAST_UPDATED_BY, CREATED_BY, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, COL004, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for hz_party_sites : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'iby_ext_bank_accounts.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_IBY_EXT_BANK_ACCOUNTS  
                        (LAST_UPDATE_DATE, CREATED_BY, BANK_ACCOUNT_NAME, BANK_ACCOUNT_NUM, BANK_ACCOUNT_TYPE, CURRENCY_CODE, LAST_UPDATED_BY, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, COL004, COL005, COL006, COL007, COL008, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for iby_ext_bank_accounts : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'iby_ext_party_pmt_mthds.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_IBY_EXT_PARTY_PMT_MTHDS  
                        (LAST_UPDATED_BY, CREATED_BY, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for iby_ext_party_pmt_mthds : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'iby_external_payees_all.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_IBY_EXTERNAL_PAYEES_ALL  
                        (LAST_UPDATED_BY, CREATED_BY, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for iby_external_payees_all : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'iby_payment_methods_tl.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_IBY_PAYMENT_METHODS_TL  
                        (LAST_UPDATE_DATE, LAST_UPDATED_BY, CREATED_BY, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, COL004, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for iby_payment_methods_tl : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'itgc_azn_menus.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_ITGC_AZN_MENUS  
                        (RESPONSIBILITY_NAME, MENU_ID, MENU_NAME, SUB_MENU_ID, IRM_CUST_ID, IRM_JOB_ID)  
                            SELECT COL001, COL002, COL003, COL004, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    -- Missing log entry and update statement 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for itgc_azn_menus : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'mtl_categories.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_MTL_CATEGORIES  
                        (CATEGORY_ID, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                            SELECT COL001, COL002, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for mtl_categories : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'mtl_parameters.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDD0_MTL_PARAMETERS  
                        (MASTER_ORGANIZATION_ID, ORGANIZATION_ID, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                            SELECT COL001, COL002, COL003, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for mtl_parameters : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'mtl_system_items_b.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_MTL_SYSTEM_ITEMS_B  
                        (INVENTORY_ITEM_ID, ORGANIZATION_ID, SEGMENT1, DESCRIPTION, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                            SELECT COL001, COL002, COL003, COL004, COL005, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for mtl_system_items_b : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'oe_order_headers_all.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_OE_ORDER_HEADERS_ALL  
                        (ORDER_NUMBER, ORDERED_DATE, TRANSACTIONAL_CURR_CODE, SOLD_TO_ORG_ID, ORG_ID, CREATED_BY, LAST_UPDATED_BY, CREATION_DATE, ORDER_TYPE_ID, HEADER_ID,  
                        LAST_UPDATE_DATE, SHIP_FROM_ORG_ID, SHIP_TO_ORG_ID, INVOICE_TO_ORG_ID, IRM_CUST_ID, IRM_JOB_ID)  
                            SELECT COL001, COL002, COL003, COL004, COL005,COL006, COL007, COL008, COL009, COL010, COL011, COL012, COL013, COL014, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for oe_order_headers_all : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'oe_order_lines_all.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_OE_ORDER_LINES_ALL  
                        (HEADER_ID, LINE_NUMBER, SHIPMENT_NUMBER, OPTION_NUMBER, COMPONENT_NUMBER, SERVICE_NUMBER, INVENTORY_ITEM_ID, ORDER_QUANTITY_UOM, ORDERED_QUANTITY, UNIT_SELLING_PRICE, 
                        CREATED_BY, LAST_UPDATED_BY, CREATION_DATE, LAST_UPDATE_DATE, LINE_ID, ATTRIBUTE15, IRM_CUST_ID, IRM_JOB_ID)  
                            SELECT COL001, COL002, COL003, COL004, COL005,COL006, COL007, COL008, COL009, COL010, COL011, COL012, COL013, COL014, COL015, COL016, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for oe_order_lines_all : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'oe_transaction_types_tl.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_OE_TRANSACTION_TYPES_TL  
                        (NAME, TRANSACTION_TYPE_ID, LANGUAGE, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                            SELECT COL001, COL002, COL003, COL004, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for oe_transaction_types_tl : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'org_organization_definitions.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_ORG_ORGANIZATION_DEFINITIONS  
                        (DISABLE_DATE, BUSINESS_GROUP_ID, USER_DEFINITION_ENABLE_DATE, ORGANIZATION_CODE, ORGANIZATION_NAME, SET_OF_BOOKS_ID, CHART_OF_ACCOUNTS_ID, INVENTORY_ENABLED_FLAG,  
                        OPERATING_UNIT, LEGAL_ENTITY, IRM_CUST_ID, IRM_JOB_ID)  
                            SELECT COL001, COL002, COL003, COL004, COL005, COL006, COL007, COL008, COL009, COL010, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for org_organization_definitions : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'pay_backpay_sets.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_PAY_BACKPAY_SETS  
                        (LAST_UPDATE_DATE, LAST_UPDATED_BY, CREATED_BY, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                            SELECT COL001, COL002, COL003, COL004, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for pay_backpay_sets : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'pay_consolidation_sets.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_PAY_CONSOLIDATION_SETS  
                        (LAST_UPDATED_BY, CREATED_BY, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                            SELECT COL001, COL002, COL003, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
                     
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for pay_consolidation_sets : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
                     
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'pay_element_sets_tl.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_PAY_ELEMENT_SETS_TL  
                        (LAST_UPDATED_BY, CREATED_BY, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                            SELECT COL001, COL002, COL003, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
                     
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for pay_element_sets_tl : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
                     
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'pay_freq_rule_periods.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_PAY_FREQ_RULE_PERIODS  
                        (LAST_UPDATE_DATE, LAST_UPDATED_BY, CREATED_BY, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                            SELECT COL001, COL002, COL003, COL004, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
                     
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for pay_freq_rule_periods : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
                     
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'pay_input_values_f.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_PAY_INPUT_VALUES_F  
                            (LAST_UPDATE_DATE, LAST_UPDATED_BY, CREATED_BY, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, COL004, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for pay_input_values_f : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'pay_org_payment_methods_f.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_PAY_ORG_PAYMENT_METHODS_F  
                            (LAST_UPDATE_DATE, LAST_UPDATED_BY, CREATED_BY, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, COL004, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for pay_org_payment_methods_f : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END;     
            ELSIF LOWER(v_file_data(i).file_name) = 'per_all_assignments_f.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_PER_ALL_ASSIGNMENTS_F  
                            (LAST_UPDATED_BY, CREATED_BY, CREATION_DATE, PERSON_ID, EFFECTIVE_START_DATE, EFFECTIVE_END_DATE, JOB_ID, POSITION_ID, LOCATION_ID, BUSINESS_GROUP_ID,  
                            ORGANIZATION_ID, ASSIGNMENT_ID, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, COL004, COL005, COL006, COL007, COL008, COL009, COL010, COL011, COL012, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for per_all_assignments_f : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'per_all_people_f.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_PER_ALL_PEOPLE_F  
                            (FULL_NAME, PERSON_ID, EFFECTIVE_START_DATE, EFFECTIVE_END_DATE, CREATION_DATE, CREATED_BY, LAST_UPDATED_BY, EMPLOYEE_NUMBER, LAST_UPDATE_DATE, PERSON_TYPE_ID, 
                            IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, COL004, COL005, COL006, COL007, COL008, COL009, COL010, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for per_all_people_f : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID'  
                    USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'per_all_positions.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_PER_ALL_POSITIONS  
                            (LAST_UPDATED_BY, CREATED_BY, NAME, POSITION_ID, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, COL004, COL005, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for per_all_positions : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'per_jobs.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_PER_JOBS  
                            (LAST_UPDATED_BY, CREATED_BY, JOB_ID, NAME, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, COL004, COL005, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for per_jobs : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END;    
            ELSIF LOWER(v_file_data(i).file_name) = 'per_pay_bases.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_PER_PAY_BASES  
                            (LAST_UPDATED_BY, CREATED_BY, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for per_pay_bases : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'per_pay_proposal_components.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_PER_PAY_PROPOSAL_COMPONENTS  
                            (LAST_UPDATE_DATE, LAST_UPDATED_BY, CREATED_BY, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, COL004, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for per_pay_proposal_components : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'per_pay_proposals.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_PER_PAY_PROPOSALS  
                            (PROPOSED_SALARY, PAY_PROPOSAL_ID, ASSIGNMENT_ID, CREATED_BY, LAST_UPDATED_BY, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                        SELECT COL001, COL002, COL003, COL004, COL005, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for per_pay_proposals : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'per_performance_reviews.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_PER_PERFORMANCE_REVIEWS  
                        (LAST_UPDATE_DATE, LAST_UPDATED_BY, CREATED_BY, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                            SELECT COL001, COL002, COL003, COL004, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for per_performance_reviews : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID'  
                    USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'per_person_types.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_PER_PERSON_TYPES  
                        (LAST_UPDATED_BY, CREATED_BY, CREATION_DATE, PERSON_TYPE_ID, BUSINESS_GROUP_ID, ACTIVE_FLAG, DEFAULT_FLAG, SYSTEM_PERSON_TYPE, USER_PERSON_TYPE, LAST_UPDATE_DATE, 
                        LAST_UPDATE_LOGIN, SEEDED_PERSON_TYPE_KEY, ZD_EDITION_NAME, ZD_SYNC, IRM_CUST_ID, IRM_JOB_ID)  
                            SELECT COL001, COL002, COL003, COL004, COL005, COL006, COL007, COL008, COL009, COL0101, COL011, COL012, COL013, COL014, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for per_person_types : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'po_action_history.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_PO_ACTION_HISTORY  
                        (LAST_UPDATED_BY, CREATED_BY, CREATION_DATE, OBJECT_ID, OBJECT_TYPE_CODE, OBJECT_SUB_TYPE_CODE, SEQUENCE_NUM, LAST_UPDATE_DATE, ACTION_CODE,  
                        ACTION_DATE, EMPLOYEE_ID, APPROVAL_PATH_ID, NOTE, LAST_UPDATE_LOGIN, IRM_CUST_ID, IRM_JOB_ID)  
                            SELECT COL001, COL002, COL003, COL004, COL005, COL006, COL007, COL008, COL009, COL010, COL011, COL012, COL013, COL014, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for po_action_history : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'po_distributions_all.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_PO_DISTRIBUTIONS_ALL  
                        (PO_HEADER_ID, PO_LINE_ID, DESTINATION_ORGANIZATION_ID, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                            SELECT COL001, COL002, COL003, COL004, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for po_distributions_all : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'po_headers_all.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_PO_HEADERS_ALL  
                        (SEGMENT1, VENDOR_ID, PO_HEADER_ID, VENDOR_SITE_ID, ORG_ID, AGENT_ID, TYPE_LOOKUP_CODE, CLOSED_CODE, CREATED_BY, LAST_UPDATED_BY, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                            SELECT COL001, COL002, COL003, COL004, COL005, COL006, COL007, COL008, COL009, COL010, COL011, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for po_headers_all : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'po_lines_all.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_PO_LINES_ALL  
                        (PO_HEADER_ID, PO_LINE_ID, UNIT_PRICE, QUANTITY, CREATED_BY, LAST_UPDATED_BY, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                            SELECT COL001, COL002, COL003, COL004, COL005, COL006, COL007, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for po_lines_all : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'po_lookup_codes.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_PO_LOOKUP_CODES  
                        (LOOKUP_TYPE, LOOKUP_CODE, DISPLAYED_FIELD, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                            SELECT COL001, COL002, COL003, COL004, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for po_lookup_codes : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'po_requisition_headers_all.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_PO_REQUISITION_HEADERS_ALL  
                        (REQUISITION_HEADER_ID, PREPARER_ID, LAST_UPDATE_DATE, LAST_UPDATED_BY, SEGMENT1, CREATED_BY, DESCRIPTION,  
                        AUTHORIZATION_STATUS, NOTE_TO_AUTHORIZER, TYPE_LOOKUP_CODE, 
                        CANCEL_FLAG, ORG_ID, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                            SELECT COL001, COL002, COL003, COL004, COL005, COL006, COL007, COL008, COL009, COL010, COL011, COL012, COL013, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for po_requisition_headers_all : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID'  
                    USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'po_requisition_lines_all.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_PO_REQUISITION_LINES_ALL  
                        (UNIT_PRICE, DESTINATION_ORGANIZATION_ID, TO_PERSON_ID, DELIVER_TO_LOCATION_ID, CATEGORY_ID, ITEM_ID, REQUISITION_HEADER_ID, CANCEL_FLAG, CREATED_BY,  
                        LAST_UPDATED_BY, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                            SELECT COL001, COL002, COL003, COL004, COL005, COL006, COL007, COL008, COL009, COL010, COL011, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for po_requisition_lines_all : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            -- ELSIF LOWER(v_file_data(i).file_name) = 'profile_option.csv' THEN 
            --     BEGIN 
            --         EXECUTE IMMEDIATE  
            --             'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_PROFILE_OPTION  
            --             (PROFILE_OPTION_ID, PROFILE_OPTION_NAME, USER_PROFILE_OPTION_NAME, LEVEL_NAME, LEVEL_VALUE, PROFILE_OPTION_VALUE_SET, RECOMMENDED_PROF_OPTION_VALUE,  
            --             LAST_UPDATED_BY_USER, LAST_UPDATE_DATE, IRM_CUST_ID, IRM_JOB_ID)  
            --                 SELECT COL001, COL002, COL003, COL004, COL005, COL006, COL007, COL008, COL009, :P0_CUST_ID, :P9_ID 
            --             FROM TABLE( 
            --                 APEX_DATA_PARSER.parse( 
            --                     p_content   => :file_blob, 
            --                     p_file_name => :file_name 
            --                 ) 
            --             ) OFFSET 1 ROWS' 
            --         USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
            --         INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for profile_option : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
            --         EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
            --     EXCEPTION WHEN OTHERS  
            --         THEN 
            --             v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
            --             INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
            --             VALUES(v_error_msg, 2, p_sync_header_id); 
            --         COMMIT; 
 
            --         EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
            --     END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'ra_batch_sources.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_RA_BATCH_SOURCES  
                        (LAST_UPDATED_BY, CREATED_BY, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                            SELECT COL001, COL002, COL003, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for ra_batch_sources : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'ra_cust_trx_line_gl_dist_all.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_RA_CUST_TRX_LINE_GL_DIST_ALL  
                        (CODE_COMBINATION_ID, CUSTOMER_TRX_ID, CUSTOMER_TRX_LINE_ID, CUST_TRX_LINE_GL_DIST_ID, IRM_CUST_ID, IRM_JOB_ID)  
                            SELECT COL001, COL002, COL003, COL004, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for ra_cust_trx_line_gl_dist_all : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'ra_cust_trx_types_all.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_RA_CUST_TRX_TYPES_ALL  
                        (CUST_TRX_TYPE_ID, NAME, TYPE, CREATED_BY, LAST_UPDATED_BY, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                            SELECT COL001, COL002, COL003, COL004, COL005, COL006, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for ra_cust_trx_types_all : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'ra_customer_trx_all.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_RA_CUSTOMER_TRX_ALL  
                        (TRX_NUMBER, TRX_DATE, BILL_TO_CUSTOMER_ID, CUSTOMER_TRX_ID, BILL_TO_SITE_USE_ID, SHIP_TO_SITE_USE_ID, CUST_TRX_TYPE_ID, CREATED_BY, 
                        LAST_UPDATED_BY, ORG_ID, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                            SELECT COL001, COL002, COL003, COL004, COL005, COL006, COL007, COL008, COL009, COL010, COL011, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for ra_customer_trx_all : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'ra_customer_trx_lines_all.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_RA_CUSTOMER_TRX_LINES_ALL  
                        (LINE_NUMBER, INTERFACE_LINE_ATTRIBUTE1, INTERFACE_LINE_ATTRIBUTE6, CUSTOMER_TRX_ID, LINE_TYPE, QUANTITY_ORDERED, UNIT_SELLING_PRICE, DESCRIPTION, 
                        CREATION_DATE, INVENTORY_ITEM_ID, CUSTOMER_TRX_LINE_ID, CREATED_BY, LAST_UPDATED_BY, IRM_CUST_ID, IRM_JOB_ID)  
                            SELECT COL001, COL002, COL003, COL004, COL005, COL006, COL007, COL008, COL009, COL010, COL011, COL012, COL013, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for ra_customer_trx_lines_all : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'ra_terms.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_RA_TERMS  
                        (LAST_UPDATED_BY, CREATED_BY, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                            SELECT COL001, COL002, COL003, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for ra_terms : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'resp_conc_programs.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_RESP_CONC_PROGRAMS  
                        (APP_ID, RESP_ID, CONC_PROG_ID, IRM_CUST_ID, IRM_JOB_ID)  
                            SELECT COL001, COL002, COL003, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for resp_conc_programs : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'user_type.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_USER_TYPE  
                        (USER_NAME, DESCRIPTION, START_DATE, END_DATE, USER_ACCOUNT_TYPE, IRM_CUST_ID, IRM_JOB_ID)  
                            SELECT COL001, COL002, COL003, COL004, COL005, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for user_type : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'xla_ae_headers.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_XLA_AE_HEADERS  
                        (EVENT_ID, APPLICATION_ID, EVENT_TYPE_CODE, ENTITY_ID, CREATED_BY, LAST_UPDATE_DATE, LAST_UPDATED_BY, LAST_UPDATE_LOGIN, PROGRAM_UPDATE_DATE, PROGRAM_APPLICATION_ID,  
                        PROGRAM_ID, REQUEST_ID, UPG_BATCH_ID, UPG_SOURCE_APPLICATION_ID, UPG_VALID_FLAG, AE_HEADER_ID, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                            SELECT COL001, COL002, COL003, COL004, COL005, COL006, COL007, COL008, COL009, COL010, COL012, COL013, COL014, COL015, COL016, COL017, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for xla_ae_headers : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'xla_ae_lines.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_XLA_AE_LINES  
                        (LAST_UPDATED_BY, CREATED_BY, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                            SELECT COL001, COL002, COL003, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for xla_ae_lines : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'xla_distribution_links.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_XLA_DISTRIBUTION_LINKS  
                        (AE_HEADER_ID, AE_LINE_NUM, SOURCE_DISTRIBUTION_ID_NUM_1, IRM_CUST_ID, IRM_JOB_ID)  
                            SELECT COL001, COL002, COL003, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for xla_distribution_links : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'xla_events.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_XLA_EVENTS  
                        (LAST_UPDATED_BY, CREATED_BY, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                            SELECT COL001, COL002, COL003, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for xla_events : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            ELSIF LOWER(v_file_data(i).file_name) = 'xla_transaction_entities.csv' THEN 
                BEGIN 
                    EXECUTE IMMEDIATE  
                        'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_XLA_TRANSACTION_ENTITIES  
                        (LAST_UPDATED_BY, CREATED_BY, CREATION_DATE, IRM_CUST_ID, IRM_JOB_ID)  
                            SELECT COL001, COL002, COL003, :P0_CUST_ID, :P9_ID 
                        FROM TABLE( 
                            APEX_DATA_PARSER.parse( 
                                p_content   => :file_blob, 
                                p_file_name => :file_name 
                            ) 
                        ) OFFSET 1 ROWS' 
                    USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
                    INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for xla_transaction_entities : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
                EXCEPTION WHEN OTHERS  
                    THEN 
                        v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
                        INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
                        VALUES(v_error_msg, 2, p_sync_header_id); 
                    COMMIT; 
 
                    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
                END; 
            -- ELSIF LOWER(v_file_data(i).file_name) = 'itgc_profile_setting.csv' THEN 
            --     BEGIN 
            --         EXECUTE IMMEDIATE  
            --             'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_ITGC_PROFILE_SETTING  
            --             (PROFILE_OPTION_ID, CONTROL_CHECK, CONTROL_ATTRIBUTE, RISK_DESCRIPTION, SETTING_VALUE, ACCESS_LEVEL_ID, ACCESS_LEVEL, APPLICATION_ID, APPLICATION_SHORT_NAME, IRM_CUST_ID, IRM_JOB_ID)  
            --                 SELECT COL001, COL002, COL003, COL004, COL005, COL006, COL007, COL008, COL009, :P0_CUST_ID, :P9_ID 
            --             FROM TABLE( 
            --                 APEX_DATA_PARSER.parse( 
            --                     p_content   => :file_blob, 
            --                     p_file_name => :file_name 
            --                 ) 
            --             ) OFFSET 1 ROWS' 
            --         USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
            --         INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for itgc_profile_setting : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
            --         EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
            --     EXCEPTION WHEN OTHERS  
            --         THEN 
            --             v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
            --             INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
            --             VALUES(v_error_msg, 2, p_sync_header_id); 
            --         COMMIT; 
 
            --         EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID' USING p_sync_header_id; 
            --     END; 
            -- ELSIF LOWER(v_file_data(i).file_name) = 'itac_extract_matching.csv' THEN 
            --     BEGIN 
            --         EXECUTE IMMEDIATE  
            --             'INSERT INTO ' || p_schema_name || '.XX_EBS_DIDDO_ITAC_EXTRACT_MATCHING  
            --             (CONTROL_ID, CONTROL_NAME, BUSINESS_UNIT, ALLOW_FINAL_MATCHING, ALLOW_DISTRBTN_LEVEL_MATCHING, ALLOW_FORCE_APPROVAL_FLAG, HOLD_UNMATCHED_INVOICES_FLAG,  
            --             ALLOW_MATCHNG_ACCT_OVERRIDE, ALLOW_REMIT_TO_ACCT_OVERRIDE, REQUIRE_VALIDTN_BEFR_APPROVAL, USE_INVOICE_APPROVAL_WORKFLOW, ALLOW_REMIT_TO_SUPPLR_OVERRIDE,  
            --             ALLOW_ADJUSTMTS_TO_PAID_INVCES, IRM_CUST_ID, IRM_JOB_ID)  
            --                 SELECT COL001, COL002, COL003, COL004, COL005, COL006, COL007, COL008, COL009, COL010, COL011, COL012, COL013, :P0_CUST_ID, :P9_ID 
            --             FROM TABLE( 
            --                 APEX_DATA_PARSER.parse( 
            --                     p_content   => :file_blob, 
            --                     p_file_name => :file_name 
            --                 ) 
            --             ) OFFSET 1 ROWS' 
            --         USING p_cust_id, p_sync_header_id, v_file_data(i).file_blob, v_file_data(i).file_name; 
 
            --         INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) VALUES('Insertion completed for itac_extract_matching : ' || v_file_data(i).file_name, 2, p_sync_header_id); 
 
            --         EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_ZIP_EXTRACT_FILES SET IS_INSERTED = ''Y'' WHERE ID = :ID' USING v_file_data(i).ID; 
            --     EXCEPTION WHEN OTHERS  
            --         THEN 
            --             v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
            --             INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID, IRM_JOB_ID) 
            --             VALUES(v_error_msg, 2, p_sync_header_id); 
            --         COMMIT; 
 
            --         EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Error Occurred in File Sync Process'' WHERE ID = :ID'  
            --         USING p_sync_header_id; 
            --     END; 
            ELSE 
                -- Additional condition and logic can go here (for ELSIF condition) 
                -- Handle no matching data 
                DBMS_OUTPUT.PUT_LINE('No data matches the condition.'); 
            END IF; 
 
        -- END LOOP; 
 
    END LOOP; 
 
    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SYNC_HEADER SET STATUS = ''Data Loading Finished'' WHERE ID = :ID' USING p_sync_header_id; 
    -- Commit the transaction 
    COMMIT; 
 
    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SOD_MST SET IRM_JOB_ID = :p_sync_header_id where IRM_JOB_ID is null' USING p_sync_header_id; --- to update Sync id in control master 
 
    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SOD_ACCESS_GRP SET IRM_JOB_ID = :p_sync_header_id where IRM_JOB_ID is null' USING p_sync_header_id; --- to update Sync id in AG master 
 
    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_SOD_FUNCTION_MST SET IRM_JOB_ID = :p_sync_header_id where IRM_JOB_ID is null' USING p_sync_header_id; --- to update Sync id in Func master 
 
    EXECUTE IMMEDIATE 'UPDATE ' || p_schema_name || '.XX_EBS_DATASOURCE SET IS_SYNCED = ''Y'' where ID = :datasource_id' USING v_datasource_id; 
 
    -- EXCEPTION WHEN OTHERS 
    --     THEN  
    --         v_error_msg := 'Error in Inserting Data for : ' || v_file_data(i).file_name || ' ' || SQLERRM; 
    --         INSERT INTO XX_SOD_SYNC_PROCESS_LOG(LOG_MSG, PROCESS_ID) 
    --         VALUES(v_error_msg, 2); 
    --     COMMIT; 
END;
/
create or replace PROCEDURE SP_UPDATE_INSERT_CLIENT_FEEDBACK ( 
    p_rating        IN NUMBER, 
    p_response      IN VARCHAR2, 
    p_feedback_type IN VARCHAR2, 
    p_client_id     IN NUMBER, 
    p_app_id        IN NUMBER, 
    p_file_blob     IN BLOB DEFAULT NULL, 
    p_file_mimetype IN VARCHAR2 DEFAULT NULL, 
    p_filename      IN VARCHAR2 DEFAULT NULL, 
    p_created_by    IN VARCHAR2 DEFAULT NULL 
) AS 
    v_id NUMBER; 
BEGIN 
     
    BEGIN 
        SELECT ID 
        INTO v_id 
        FROM TRN_CLIENT_APP_FEEDBACK 
        WHERE CLIENT_ID = p_client_id 
          AND APP_ID = p_app_id 
          AND FEEDBACK_TYPE = p_feedback_type 
        FOR UPDATE; 
 
         
        UPDATE TRN_CLIENT_APP_FEEDBACK 
        SET RATING = p_rating, 
            RESPONSE = p_response, 
            UPDATED_BY = SYS_CONTEXT('APEX$SESSION', 'APP_USER'), 
            UPDATED_AT = CURRENT_TIMESTAMP 
        WHERE ID = v_id; 
     
    EXCEPTION 
        WHEN NO_DATA_FOUND THEN 
             
            INSERT INTO TRN_CLIENT_APP_FEEDBACK ( 
                CLIENT_ID, APP_ID, FEEDBACK_TYPE, RESPONSE, STATUS, IS_ACTIVE, CREATED_BY, CREATED_AT, RATING 
            ) VALUES ( 
                p_client_id, p_app_id, p_feedback_type, p_response, 'O', 'Y', SYS_CONTEXT('APEX$SESSION', 'APP_USER'), CURRENT_TIMESTAMP, p_rating 
            ) RETURNING ID INTO v_id;  
    END; 
 
     
    IF p_file_blob IS NOT NULL THEN 
        INSERT INTO TRN_CLIENT_APP_FEEDBACK_ATTACHMENTS ( 
            FEEDBACK_ID, FILE_BLOB, FILE_MIMETYPE, FILENAME, CREATED_BY, CREATED_AT, IS_ACTIVE 
        ) VALUES ( 
            v_id, p_file_blob, p_file_mimetype, p_filename, NVL(p_created_by, SYS_CONTEXT('APEX$SESSION', 'APP_USER')), CURRENT_TIMESTAMP, 'Y' 
        ); 
    END IF; 
 
EXCEPTION 
    WHEN OTHERS THEN 
        RAISE; 
END SP_UPDATE_INSERT_CLIENT_FEEDBACK;
/
create or replace PROCEDURE SP_UPDATE_RMC_JOB_STATUS_V2 --USING
(
    v_schema_name IN VARCHAR2 DEFAULT 'IRM_SA_ACCESS',
    p_id IN NUMBER
) AS 
    l_status VARCHAR2(100); 
    l_clob CLOB; 
    l_url VARCHAR2(1000); 
    l_username VARCHAR2(100); 
    l_password VARCHAR2(100);

    v_ormc_id number;
    v_profile_id number;
    v_auth_type varchar2(200);
    v_jwt_token clob;
BEGIN
    --CODE BLOCK 1
    BEGIN
        EXECUTE IMMEDIATE
        'SELECT RMC_RESULT_ID, PROFILE_ID FROM '|| v_schema_name ||'.TRN_SIMULATION_JOBS WHERE ID = :p_id
        ' INTO v_ormc_id, v_profile_id USING p_id;

    EXCEPTION WHEN OTHERS THEN
        IRM_GLOBAL_APP_CONFIG.SP_ERROR_LOGGER_V1
            (
                p_client_id => 0,
                p_err_src => 'WORKFLOW : SP_UPDATE_RMC_JOB_STATUS_V2 : CODE BLOCK 1',
                p_err_msg => SQLERRM
            );
    END;


    -- Fetch connection details 
    SELECT ERP_URL, AUTH_TYPE 
        INTO l_url, v_auth_type
    FROM IRM_GLOBAL_APP_CONFIG.MST_CLIENT_ERP_CONFIG 
    WHERE id = v_profile_id;


    -- Prepare the request body 
    apex_json.initialize_clob_output; 
    apex_json.open_object;
    apex_json.write('requestId', v_ormc_id);
    apex_json.close_object;
    l_clob := apex_json.get_clob_output;
    apex_json.free_output;

    -- Make the API call
    apex_web_service.g_request_headers(1).name := 'Content-Type';
    apex_web_service.g_request_headers(1).value := 'application/vnd.oracle.adf.action+json';

    if v_auth_type = 'JWT' then

        v_jwt_token := IRM_GLOBAL_APP_CONFIG.FN_GENERATE_JWT_TOKEN_V1(v_profile_id);

        apex_web_service.g_request_headers(2).name := 'Authorization';
        apex_web_service.g_request_headers(2).value := 'Bearer ' || v_jwt_token;

        l_clob := apex_web_service.make_rest_request( 
            p_url => l_url || '/fscmRestApi/resources/11.13.18.05/advancedControlsRolesProvisioning/action/getRequestStatus', 
            p_http_method => 'POST', 
            p_body => l_clob
        );

    else

        SELECT ERP_USERNAME, ERP_PASSWORD, ERP_URL 
            INTO l_username, l_password, l_url
        FROM IRM_GLOBAL_APP_CONFIG.MST_CLIENT_ERP_CONFIG 
        WHERE id = v_profile_id;

        l_clob := apex_web_service.make_rest_request( 
            p_url => l_url || '/fscmRestApi/resources/11.13.18.05/advancedControlsRolesProvisioning/action/getRequestStatus', 
            p_http_method => 'POST', 
            p_body => l_clob, 
            p_username => l_username, 
            p_password => l_password 
        );
    end if;
    
 
    -- Parse the response 
    apex_json.parse(l_clob); 
    l_status := apex_json.get_varchar2(p_path => 'result');

    IF LOWER(l_status) = 'completed' then

        EXECUTE IMMEDIATE
        'BEGIN
            '|| v_schema_name ||'.SP_SOD_RESULT_SAVE_V2(:1, :2);
        END;'
        USING v_schema_name, p_id;

    end if;
     
    -- Update the table dynamically 
    EXECUTE IMMEDIATE 'UPDATE ' || v_schema_name || '.TRN_SIMULATION_JOBS  
                      SET RESULT_STATUS = :l_status 
                      WHERE ID = :p_id' 
        USING l_status, p_id; 
 
    COMMIT; 
EXCEPTION 
    WHEN OTHERS THEN 
        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM); 
        ROLLBACK;
END;
/ 