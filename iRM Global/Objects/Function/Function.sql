create or replace FUNCTION call_cohere (
    p_prompt IN VARCHAR2
) RETURN CLOB IS
    l_url          VARCHAR2(1000) := 'https://api.cohere.ai/v1';
    l_http_req     UTL_HTTP.req;
    l_http_resp    UTL_HTTP.resp;
    l_response     CLOB;
    l_buffer       VARCHAR2(4000);
    l_api_key      VARCHAR2(100) := 'Thc217nKvz7gziz2md3MFlEgj9dOfhNmsbFmc0sx';
    l_payload      CLOB;
BEGIN
    -- If you're on ADB, set your wallet path
    -- UTL_HTTP.set_wallet('file:/wallet_location', 'your_wallet_password');

    -- Build proper payload
    l_payload := '{
      "model": "cohere.command-r-16k",
      "chat_history": [],
      "message": "' || REPLACE(REPLACE(p_prompt, '"', '\"'), CHR(10), '\n') || '",
      "temperature": 0.5
    }';

    l_http_req := UTL_HTTP.begin_request(l_url, 'POST', 'HTTP/1.1');
    UTL_HTTP.set_header(l_http_req, 'Content-Type', 'application/json');
    UTL_HTTP.set_header(l_http_req, 'Authorization', 'Bearer ' || l_api_key);
    UTL_HTTP.set_header(l_http_req, 'Accept', 'application/json');

    UTL_HTTP.write_text(l_http_req, l_payload);

    l_http_resp := UTL_HTTP.get_response(l_http_req);

    DBMS_LOB.createtemporary(l_response, TRUE);
    LOOP
        UTL_HTTP.read_line(l_http_resp, l_buffer, TRUE);
        DBMS_LOB.writeappend(l_response, LENGTH(l_buffer), l_buffer);
    END LOOP;

    UTL_HTTP.end_response(l_http_resp);

    RETURN l_response;

EXCEPTION
    WHEN UTL_HTTP.end_of_body THEN
        UTL_HTTP.end_response(l_http_resp);
        RETURN l_response;
    WHEN OTHERS THEN
        RETURN 'Error: ' || SQLERRM;
END;
/
create or replace FUNCTION FN_ADD_BOOKMARK( 
    p_client_id NUMBER, 
    p_user_id NUMBER, 
    p_app_id NUMBER, 
    p_page_id NUMBER 
) 
RETURN VARCHAR2 
IS 
    l_msg VARCHAR2(1000); 
    l_check_if_bookmark_exists NUMBER; 
    l_bookmark_exists_active_state NUMBER; 
BEGIN 
    /* 
        Function created by Racktim Guin 
        for adding page in the bookmark list 
    */ 
 
    -- check if Bookmark for this page already exists in active state 
    SELECT COUNT(ID) INTO l_bookmark_exists_active_state FROM TRN_APP_USER_BOOKMARKS 
    WHERE CLIENT_ID = p_client_id 
    AND APP_ID = p_app_id 
    AND USER_ID = p_user_id 
    AND PAGE_ID = p_page_id 
    AND IS_ACTIVE = 'Y'; 
 
    IF l_bookmark_exists_active_state > 0 
        THEN 
        -- bookmark exists so we will remove it 
        UPDATE TRN_APP_USER_BOOKMARKS SET IS_ACTIVE = 'N' 
        WHERE CLIENT_ID = p_client_id 
            AND APP_ID = p_app_id 
            AND USER_ID = p_user_id 
            AND PAGE_ID = p_page_id 
            AND IS_ACTIVE = 'Y'; 
         
        l_msg := 'Bookmark removed Successfully!'; 
    ELSE 
        -- bookmark does not exists so we will add it 
        -- check if the particular user has limit for bookmark addition 
        IF FN_GET_REMAIN_BOOKMARK_LIMIT( 
            p_client_id => p_client_id, 
            p_user_id => p_user_id, 
            p_app_id => p_app_id 
        ) > 0 
            THEN 
            -- check if Bookmark for this page already exists but in inactive state 
            SELECT COUNT(ID) INTO l_check_if_bookmark_exists FROM TRN_APP_USER_BOOKMARKS 
            WHERE CLIENT_ID = p_client_id 
            AND APP_ID = p_app_id 
            AND USER_ID = p_user_id 
            AND PAGE_ID = p_page_id 
            AND IS_ACTIVE = 'N'; 
 
            IF l_check_if_bookmark_exists > 0 
                THEN 
                -- update the bookmark to Active state 
                UPDATE TRN_APP_USER_BOOKMARKS SET IS_ACTIVE = 'Y' 
                WHERE CLIENT_ID = p_client_id 
                    AND APP_ID = p_app_id 
                    AND USER_ID = p_user_id 
                    AND PAGE_ID = p_page_id 
                    AND IS_ACTIVE = 'N'; 
            ELSE 
                -- insert into TRN_APP_USER_BOOKMARKS 
                INSERT INTO TRN_APP_USER_BOOKMARKS(CLIENT_ID, APP_ID, USER_ID, PAGE_ID) 
                VALUES(p_client_id, p_app_id, p_user_id, p_page_id); 
            END IF; 
 
            l_msg := 'Successfully added to Bookmark!'; 
        ELSE 
            l_msg := 'You have reached your Max Bookmark limit. Please remove one first!!'; 
        END IF; 
 
    END IF; 
 
    RETURN l_msg; 
END;
/
create or replace FUNCTION FN_ADD_REMOVE_BOOKMARK( 
    p_client_id NUMBER, 
    p_user_id NUMBER, 
    p_app_id NUMBER, 
    p_page_id NUMBER 
) 
RETURN VARCHAR2 
IS 
    l_msg VARCHAR2(1000); 
    l_check_if_bookmark_exists NUMBER; 
    l_bookmark_exists_active_state NUMBER; 
BEGIN 
    /* 
        Function created by Racktim Guin 
        for adding page in the bookmark list 
    */ 
 
    -- check if Bookmark for this page already exists in active state 
    SELECT COUNT(ID) INTO l_bookmark_exists_active_state FROM TRN_APP_USER_BOOKMARKS 
    WHERE CLIENT_ID = p_client_id 
    AND APP_ID = p_app_id 
    AND USER_ID = p_user_id 
    AND PAGE_ID = p_page_id 
    AND IS_ACTIVE = 'Y'; 
 
    IF l_bookmark_exists_active_state > 0 
        THEN 
        -- bookmark exists so we will remove it 
        UPDATE TRN_APP_USER_BOOKMARKS SET IS_ACTIVE = 'N' 
        WHERE CLIENT_ID = p_client_id 
            AND APP_ID = p_app_id 
            AND USER_ID = p_user_id 
            AND PAGE_ID = p_page_id 
            AND IS_ACTIVE = 'Y'; 
         
        l_msg := 'Bookmark removed Successfully!'; 
    ELSE 
        -- bookmark does not exists so we will add it 
        -- check if the particular user has limit for bookmark addition 
        IF FN_GET_REMAIN_BOOKMARK_LIMIT( 
            p_client_id => p_client_id, 
            p_user_id => p_user_id, 
            p_app_id => p_app_id 
        ) > 0 
            THEN 
            -- check if Bookmark for this page already exists but in inactive state 
            SELECT COUNT(ID) INTO l_check_if_bookmark_exists FROM TRN_APP_USER_BOOKMARKS 
            WHERE CLIENT_ID = p_client_id 
            AND APP_ID = p_app_id 
            AND USER_ID = p_user_id 
            AND PAGE_ID = p_page_id 
            AND IS_ACTIVE = 'N'; 
 
            IF l_check_if_bookmark_exists > 0 
                THEN 
                -- update the bookmark to Active state 
                UPDATE TRN_APP_USER_BOOKMARKS SET IS_ACTIVE = 'Y' 
                WHERE CLIENT_ID = p_client_id 
                    AND APP_ID = p_app_id 
                    AND USER_ID = p_user_id 
                    AND PAGE_ID = p_page_id 
                    AND IS_ACTIVE = 'N'; 
            ELSE 
                -- insert into TRN_APP_USER_BOOKMARKS 
                INSERT INTO TRN_APP_USER_BOOKMARKS(CLIENT_ID, APP_ID, USER_ID, PAGE_ID) 
                VALUES(p_client_id, p_app_id, p_user_id, p_page_id); 
            END IF; 
 
            l_msg := 'Successfully added to Bookmark!'; 
        ELSE 
            l_msg := 'You have reached your Max Bookmark limit. Please remove one first!!'; 
        END IF; 
 
    END IF; 
 
    RETURN l_msg; 
END;
/
create or replace FUNCTION FN_APP_CUSTOM_AUTH  
  (p_username in varchar2, 
   p_password in varchar2)  
return boolean 
IS  
  l_user_exist              number; 
  l_username                varchar2(255) := lower(p_username); 
  l_password                varchar2(255); 
 
BEGIN  
  
    select count(1) into l_user_exist from MST_USERS where LOWER(EMAIL) = l_username and is_active = 'Y'; 
 
     --if the user exist 
     if l_user_exist > 0 then  
 
        select PASSWORD into l_password from MST_USERS where LOWER(EMAIL) = l_username; 
           
        if p_password = l_password then 
            dbms_output.put_line('true'); 
            return true;  
        else  
            dbms_output.put_line('false');  
            return false; 
        end if;  
 
     else  
        return false; 
    end if;  
 
 exception when others then 
    return false; 
end FN_APP_CUSTOM_AUTH;
/
create or replace FUNCTION FN_APP_CUSTOM_AUTH_GLOBAL_APP  
  (p_username in varchar2, 
   p_password in varchar2)  
return boolean 
IS  
  l_user_exist              number; 
  l_username                varchar2(2550) := lower(p_username); 
  l_password                varchar2(255); 
  l_e_password              varchar2(300); 
BEGIN  
  
    select count(1) into l_user_exist from MST_USERS where LOWER(EMAIL) = l_username and is_active = 'Y'; 
 
     --if the user exist 
    if l_user_exist > 0 then  
 
        l_e_password := oos_util_crypto.hash_str( 
            p_src => p_password,  
            p_typ => oos_util_crypto.gc_hash_sh256 
        ); 
         
        select HASH_PASSWORD into l_password from MST_USERS where LOWER(email) = l_username AND is_active = 'Y';  
 
           if l_e_password = l_password then 
              dbms_output.put_line('true'); 
              return true;  
 
            else  
                dbms_output.put_line('false');  
                return false; 
            end if; 
    else  
        return false; 
    end if;  
 
 exception when others then 
    return false; 
end FN_APP_CUSTOM_AUTH_GLOBAL_APP;
/
create or replace FUNCTION FN_CLIENT_ORG_HIER  
RETURN CLOB  
IS 
    l_html CLOB; 
     
    -- Recursive Procedure to Build Hierarchy 
    PROCEDURE BUILD_HIERARCHY (p_parent_id NUMBER, p_indent VARCHAR2, p_clob IN OUT CLOB)  
    IS 
    BEGIN 
        FOR node_rec IN ( 
            SELECT  
                mcoh.ID AS NODE_ID, 
                mcoh.PARENT_ID, 
                mcoh.CLIENT_ID, 
                mc.CLIENT_NAME || ' - ' || mcoh.ORG_HIERARCHY || ': ' || mcoh.HIER_NAME AS LABEL 
            FROM MST_CLIENT_ORG_HIER mcoh 
            JOIN MST_CLIENT mc ON mcoh.CLIENT_ID = mc.ID 
            WHERE mcoh.PARENT_ID = p_parent_id 
            AND mcoh.IS_ACTIVE = 'Y' 
            ORDER BY mcoh.HIER_NAME 
        )  
        LOOP 
            -- Start a list item 
            p_clob := p_clob || p_indent || '<li>'; 
            p_clob := p_clob || '<i class="fa fa-edit"></i> ' || node_rec.LABEL; 
            p_clob := p_clob || ' <span class="tree-link" data-id="' || node_rec.NODE_ID ||  
                      '" data-client-id="' || node_rec.CLIENT_ID ||  
                      '" onclick="openPage(this)">Edit</span>'; 
             
            -- Check if this node has children 
            DECLARE 
                l_child_count NUMBER; 
            BEGIN 
                SELECT COUNT(*) INTO l_child_count FROM MST_CLIENT_ORG_HIER  
                WHERE PARENT_ID = node_rec.NODE_ID AND IS_ACTIVE = 'Y'; 
 
                -- If there are child nodes, start a new unordered list and recurse 
                IF l_child_count > 0 THEN 
                    p_clob := p_clob || '<ul>'; 
                    BUILD_HIERARCHY(node_rec.NODE_ID, p_indent || '  ', p_clob); 
                    p_clob := p_clob || '</ul>'; 
                END IF; 
            END; 
 
            -- Close list item 
            p_clob := p_clob || '</li>'; 
        END LOOP; 
    END; 
 
BEGIN 
    l_html := '<ul class="tree-view">'; 
     
    -- Start recursion from top-level nodes (where PARENT_ID is NULL) 
    BUILD_HIERARCHY(NULL, '', l_html); 
 
    l_html := l_html || '</ul>'; 
 
    RETURN l_html; 
END FN_CLIENT_ORG_HIER;
/
create or replace FUNCTION FN_CUSTOM_NAV_AUTH 
  ( 
   p_username in varchar2,   
   p_module_id in number, 
   p_parent_module_id in number 
  )  
return varchar2  
IS  
 
  l_user_exist              number;  
  l_user_email               varchar2(255) := lower(p_username); -- lower the username, as we are loggin in using email of the user 
  l_user_id                 number; 
  l_user_role_id            number; 
  l_has_page_access         number; 
  l_all_modules             varchar2(1); -- to determine if the user has access to all the modules 
BEGIN  
 
    select count(*) into l_user_exist from MST_USERS where lower(email) = l_user_email;  
     
  
    if l_user_exist > 0 then  
     
        select ID into l_user_id from MST_USERS where lower(email) = l_user_email; 
 
    
        select role_id into l_user_role_id from TRN_USER_ROLE_MAP where user_id = l_user_id; 
         
        -- check if the current authorizing module is parent module or sub module 
        if p_parent_module_id is null then 
 
            dbms_output.put_line('Parent module id is null'); 
            select count(1) into l_has_page_access from TRN_ROLE_PERMIS_MAP  
            where role_id = l_user_role_id  
            and module_id = p_module_id; 
 
        else 
 
            dbms_output.put_line('Parent module id is not null'); 
            select count(1) into l_has_page_access from TRN_ROLE_PERMIS_MAP  
            where role_id = l_user_role_id  
            and module_id = p_parent_module_id 
            and sub_module_id = p_module_id; 
             
        end if; 
 
        -- check if the user has access to all modules 
        select count(1) into l_all_modules from TRN_ROLE_PERMIS_MAP  
        where role_id = l_user_role_id  
        and module_id = 0 
        and is_active = 'Y'; 
 
 
        if l_has_page_access > 0 or l_all_modules > 0 then 
            dbms_output.put_line('true'); 
            return 'TRUE'; 
        else 
            dbms_output.put_line('false'); 
            return 'FALSE'; 
        end if; 
      
     --if the user does not exist in the user's table return false 
     else  
          return 'FALSE';  
     end if;  
 
 exception when others then 
    return 'FALSE'; 
end FN_CUSTOM_NAV_AUTH;
/
create or replace FUNCTION FN_CUSTOM_NAV_AUTH_V2 
  ( 
   p_username in varchar2,   
   p_module_id in number, 
   p_parent_module_id in number 
  )  
RETURN VARCHAR2 
IS  
    v_result                  varchar2(500); 
    l_user_exist              number;  
    l_user_email              varchar2(255) := lower(p_username); 
    l_user_id                 number; 
    l_user_role_id            number; 
    l_has_page_access         number; 
    l_all_modules             varchar2(1); 
BEGIN  
 
    select count(1) into l_user_exist from IRM_GLOBAL_APP_CONFIG.MST_USERS where lower(email) = l_user_email; 
  
    if l_user_exist > 0 then  
     
        select ID into l_user_id from IRM_GLOBAL_APP_CONFIG.MST_USERS where lower(email) = l_user_email; 
 
        --LOOPING THROUGH EACH ROLE THAT THE USER HAS 
        for i in (select ROLE_ID FROM IRM_GLOBAL_APP_CONFIG.TRN_USER_MULTI_ROLE_MAP WHERE USER_ID = l_user_id and IS_ACTIVE = 'Y') LOOP 
 
            l_user_role_id := i.ROLE_ID; 
             
            if p_parent_module_id is null then 
 
                dbms_output.put_line('Parent module id is null'); 
 
                select count(1)  
                into l_has_page_access  
                from IRM_GLOBAL_APP_CONFIG.TRN_ROLE_PERMIS_MAP  
                where role_id = l_user_role_id  
                and module_id = p_module_id; 
 
            else 
 
                dbms_output.put_line('Parent module id is not null'); 
 
                select count(1)  
                into l_has_page_access  
                from IRM_GLOBAL_APP_CONFIG.TRN_ROLE_PERMIS_MAP  
                where role_id = l_user_role_id  
                and module_id = p_parent_module_id 
                and sub_module_id = p_module_id; 
 
            end if; 
 
            select count(1) into l_all_modules from IRM_GLOBAL_APP_CONFIG.TRN_ROLE_PERMIS_MAP  
            where role_id = l_user_role_id  
            and module_id = 0 
            and is_active = 'Y'; 
 
            if l_has_page_access > 0 or l_all_modules > 0 then 
 
                dbms_output.put_line('true'); 
                RETURN 'TRUE'; 
 
            else 
 
                dbms_output.put_line('false'); 
                v_result := 'FALSE'; 
 
            end if; 
 
        END LOOP; 
   
    ELSE 
        v_result := 'FALSE';  
    END IF;  
 
    RETURN v_result; 
 
EXCEPTION WHEN OTHERS THEN 
 
    RETURN 'FALSE'; 
 
END FN_CUSTOM_NAV_AUTH_V2;
/
create or replace function "FN_DYNAMIC_NAVIGATION" 
( 
    p_app_id number, 
    p_app_user varchar, 
    p_erp_id number Default 0 
)--CURRENLY USING NAVIAGTION FUNCTION 
return CLOB 
as 
    v_erp_id number := nvl(p_erp_id, 0); 
begin 
 
 
 
return  
    'select level, 
      MODULE_NAME AS ENTRY_TEXT, 
      (case when page_no is not null 
        then ''f?p=''||APP_NO||'':''||PAGE_NO||'':''||:APP_SESSION 
      else null 
      end) 
      as target, 
      PAGE_NO, 
      ICON, 
      ID, 
      PARENT_ID 
       
    from IRM_GLOBAL_APP_CONFIG.MST_APP_NAVIGATION CNM 
where CNM.is_active = ''Y'' 
and IRM_GLOBAL_APP_CONFIG.FN_CUSTOM_NAV_AUTH_V2('''|| p_app_user ||''', ID, PARENT_ID) = ''TRUE'' 
AND APP_NO = '|| p_app_id ||'  
 
start with parent_id is null 
connect by prior CNM.ID = PARENT_ID 
order siblings by SEQ'; 
 
-- AND (CNM.ERP = '||v_erp_id||' OR CNM.ERP IS NULL OR '||v_erp_id||' = 0) 
 
end "FN_DYNAMIC_NAVIGATION";
/
create or replace FUNCTION "FN_DYNAMIC_NAVIGATION_BAR" 
( 
    p_app_id NUMBER DEFAULT 131 
    -- p_client_id NUMBER DEFAULT 21 
 
) 
RETURN CLOB 
AS 
    l_is_super_admin VARCHAR2(1000); 
    cli_name NUMBER; 
    v_noty_cnt VARCHAR2(100); 
 
BEGIN  
 
    SELECT IS_SUPER_ADMIN 
    INTO l_is_super_admin 
    FROM MST_USERS 
    WHERE LOWER(EMAIL) = LOWER(SYS_CONTEXT('APEX$SESSION','APP_USER')); 
 
    SELECT COUNT(1) INTO v_noty_cnt FROM LOG_NOTIFICATION WHERE LOWER(USERNAME) = LOWER(SYS_CONTEXT('APEX$SESSION','APP_USER')) AND IS_ACTIVE = 'Y'; 
 
    -- SELECT CLIENT_NAME INTO cli_name from MST_CLIENT where ID = p_client_id; 
 
        RETURN  
        'SELECT LEVEL, 
            CASE  
                WHEN LABEL_NAME = ''APP_USER'' THEN LOWER(:APP_USER)
                    
                WHEN LABEL_NAME = ''CLIENT_NAME'' THEN (SELECT CLIENT_NAME FROM IRM_GLOBAL_APP_CONFIG.MST_CLIENT WHERE ID = :CLIENT_ID) 
                 WHEN LABEL_NAME = ''Choose ERP'' THEN (SELECT NAME FROM IRM_GLOBAL_APP_CONFIG.MST_ERP WHERE ID = :ERP_ID) 
                WHEN UPPER(LABEL_NAME) = ''NOTIFICATION'' THEN  '''|| TO_CHAR(v_noty_cnt) || ''' 
                ELSE LABEL_NAME  
            END AS ENTRY_TEXT, 
            (CASE  
                WHEN PAGE_NO = 9999 THEN :LOGOUT_URL 
                WHEN PAGE_NO IS NOT NULL THEN ''f?p='' || TARGET_APPLICATON || '':'' || PAGE_NO || '':'' || :APP_SESSION 
                ELSE NULL 
            END) AS TARGET, 
            PAGE_NO, 
            ICON, 
            CASE WHEN UPPER(LABEL_NAME) = ''NOTIFICATION'' THEN ''notification-icon''  
            ELSE ''attr'' END as ENTRY_ATTRIBUTE_01, 
            ID, 
            PARENT_ID 
        FROM IRM_GLOBAL_APP_CONFIG.MST_CUSTOM_NAV_BAR CNM 
        WHERE CNM.IS_ACTIVE = ''Y'' 
        AND (NOT ('|| p_app_id ||' = 131 AND SHOW_IN_GLOBAL_APP = ''N''))  
        AND (CNM.IS_SUPER_ADMIN = '''|| l_is_super_admin ||''' OR CNM.IS_SUPER_ADMIN = ''N'') 
        AND ((APP_NO = ' || p_app_id || ' OR ' || p_app_id || ' = 131) OR APP_NO IS NULL) 
        START WITH PARENT_ID IS NULL 
        CONNECT BY PRIOR CNM.ID = PARENT_ID 
        ORDER SIBLINGS BY SEQ'; 
 
EXCEPTION WHEN OTHERS THEN 
    RETURN 
        'SELECT  
            LEVEL, 
            LOWER(SYS_CONTEXT(''APEX$SESSION'',''APP_USER'')) AS ENTRY_TEXT, 
            :LOGOUT_URL AS TARGET, 
            ''fa-arrow-left-alt'' AS ICON, 
            1 AS ID, 
            NULL AS PARENT_ID 
        FROM DUAL 
        WHERE EXISTS (SELECT 1 FROM IRM_GLOBAL_APP_CONFIG.MST_CUSTOM_NAV_BAR WHERE SHOW_IN_GLOBAL_APP = ''Y'') 
        CONNECT BY LEVEL <= 1'; 
END "FN_DYNAMIC_NAVIGATION_BAR";
/
create or replace FUNCTION "FN_DYNAMIC_NAVIGATION_BAR_V2" 
( 
    p_app_id NUMBER DEFAULT 131 
    -- p_client_id NUMBER DEFAULT 21 
 
) 
RETURN CLOB 
AS 
l_is_super_admin VARCHAR2(1000); 
cli_name NUMBER; 
 
BEGIN  
 
    SELECT IS_SUPER_ADMIN 
    INTO l_is_super_admin 
    FROM MST_USERS 
    WHERE LOWER(EMAIL) = LOWER(SYS_CONTEXT('APEX$SESSION','APP_USER')); 
 
    -- SELECT CLIENT_NAME INTO cli_name from MST_CLIENT where ID = p_client_id; 
 
    RETURN  
        'SELECT LEVEL, 
 
       
 
            CASE  
                WHEN LABEL_NAME = ''APP_USER'' THEN 
                    SELECT FIRST_NAME || '' '' || LAST_NAME FROM IRM_GLOBAL_APP_CONFIG.MST_USERS where trim(lower(email)) = trim(lower(:APP_USER)) AND ROWNUM = 1
                WHEN LABEL_NAME = ''CLIENT_NAME'' THEN (SELECT CLIENT_NAME FROM MST_CLIENT WHERE ID = :CLIENT_ID) 
                WHEN LABEL_NAME = ''Choose ERP'' THEN (SELECT NAME FROM IRM_GLOBAL_APP_CONFIG.MST_ERP WHERE ID = :ERP_ID) 
                ELSE LABEL_NAME  
            END AS ENTRY_TEXT, 
            (CASE  
                WHEN PAGE_NO = 9999 THEN :LOGOUT_URL 
                WHEN PAGE_NO IS NOT NULL THEN ''f?p='' || TARGET_APPLICATON || '':'' || PAGE_NO || '':'' || :APP_SESSION 
                ELSE NULL 
            END) AS TARGET, 
            PAGE_NO, 
            ICON, 
            ID, 
            PARENT_ID 
        FROM IRM_GLOBAL_APP_CONFIG.MST_CUSTOM_NAV_BAR CNM 
        WHERE CNM.IS_ACTIVE = ''Y'' 
        AND (NOT ('|| p_app_id ||' = 131 AND SHOW_IN_GLOBAL_APP = ''N''))  
        AND (CNM.IS_SUPER_ADMIN = '''|| l_is_super_admin ||''' OR CNM.IS_SUPER_ADMIN = ''N'') 
        AND ((APP_NO = ' || p_app_id || ' OR ' || p_app_id || ' = 131) OR APP_NO IS NULL) 
        START WITH PARENT_ID IS NULL 
        CONNECT BY PRIOR CNM.ID = PARENT_ID 
        ORDER SIBLINGS BY SEQ'; 
 
EXCEPTION WHEN OTHERS THEN 
    RETURN 
        'SELECT  
            LEVEL, 
            ''Go Back'' AS ENTRY_TEXT, 
            ''f?p=131:1:&SESSION.::&DEBUG.:::'' AS TARGET, 
            NULL AS PAGE_NO, 
            ''fa-arrow-left-alt'' AS ICON, 
            1 AS ID, 
            NULL AS PARENT_ID 
        FROM DUAL 
        WHERE EXISTS (SELECT 1 FROM IRM_GLOBAL_APP_CONFIG.MST_CUSTOM_NAV_BAR WHERE SHOW_IN_GLOBAL_APP = ''Y'') 
        CONNECT BY LEVEL <= 1'; 
END "FN_DYNAMIC_NAVIGATION_BAR_V2";
/
create or replace FUNCTION FN_DYNAMIC_ORG_TREE( 
       p_client_id IN NUMBER DEFAULT NULL 
) RETURN CLOB IS 
    l_html CLOB; 
    l_prev_level NUMBER := 1; 
BEGIN 
    l_html := '<ul class="tree">'; 
 
    FOR rec IN ( 
        SELECT  
            mcoh.ID AS NODE_ID, 
            mcoh.PARENT_ID, 
            mcoh.CLIENT_ID, 
          
     '<div class="nodes"><span>' || mcoh.ORG_HIERARCHY || ': ' || mcoh.HIER_NAME || '</span> 
<i class="fa fa-caret-down" style="font-size: 24px;" onclick="expandClosest(event)"></i>  
<div class="btn" style="border: none;" 
    "background: transparent;" 
    </button>' ||'<button type="button" class="custom-btn custom-btn--edit"data-id="' || mcoh.ID || '"><span aria-hidden="true" class="t-Icon t-Icon--left fa fa-pencil"></span></button>'|| 
     '<button type="button" class="custom-btn custom-btn--add"data-client-id="' || mcoh.CLIENT_ID || '" data-parent-id="' || mcoh.ID || '"><span aria-hidden="true" class="t-Icon t-Icon--left fa fa-plus-circle-o" ></span></button></div> 
</div>' AS LABEL, 
 LEVEL AS HIERARCHY_LEVEL 
        FROM MST_CLIENT_ORG_HIER mcoh 
        JOIN MST_CLIENT mc ON mcoh.CLIENT_ID = mc.ID 
        WHERE mcoh.IS_ACTIVE = 'Y' AND (mcoh.CLIENT_ID = p_client_id OR p_client_id IS NULL) 
        START WITH mcoh.PARENT_ID IS NULL 
        CONNECT BY PRIOR mcoh.ID = mcoh.PARENT_ID 
        -- ORDER SIBLINGS BY mcoh.HIER_NAME 
        ORDER SIBLINGS BY PARENT_ID 
    ) LOOP 
        -- IF rec.HIERARCHY_LEVEL > l_prev_level THEN 
        --     l_html := l_html || '<span class="join-line"></span><ul>'; 
        -- ELSIF rec.HIERARCHY_LEVEL < l_prev_level THEN 
        --     l_html := l_html || '</ul></li>'; 
        -- ELSE 
        --     l_html := l_html || '</li>'; 
        -- END IF; 

        IF rec.HIERARCHY_LEVEL > l_prev_level THEN 
    l_html := l_html || '<span class="join-line"></span><ul>'; 
ELSIF rec.HIERARCHY_LEVEL < l_prev_level THEN
    FOR i IN 1 .. (l_prev_level - rec.HIERARCHY_LEVEL) LOOP
        l_html := l_html || '</ul></li>';
    END LOOP;
ELSE 
    l_html := l_html || '</li>'; 
END IF;-------------------------------------------------->lAST CHANGE
 
        l_html := l_html || '<li>' || rec.LABEL; 
 
        l_prev_level := rec.HIERARCHY_LEVEL; 
    END LOOP; 
 
    FOR i IN 1..l_prev_level LOOP 
        l_html := l_html || '</li></ul>'; 
    END LOOP; 
 
    RETURN l_html; 
END FN_DYNAMIC_ORG_TREE;
/
create or replace FUNCTION FN_DYNAMIC_ORG_TREE_2( 
  p_client_id IN NUMBER DEFAULT NULL 
) RETURN CLOB IS 
    l_html CLOB; 
    l_prev_level NUMBER := 0; 
BEGIN 
    -- Initialize the root UL element 
    l_html := '<ul class="tree" id="ia-share-point" style="list-style-type: none; padding-left: 0;">';  
 
    FOR rec IN ( 
        SELECT  
            mcoh.ID AS NODE_ID, 
            mcoh.PARENT_ID, 
            mcoh.CLIENT_ID, 
            '<div onclick="expandClosest(event)" class="nodes"> 
              
                    <defs> 
                        <linearGradient id="grad' || mcoh.ID || '" x1="0%" y1="0%" x2="100%" y2="100%"> 
                            <stop offset="0%" style="stop-color: rgba(255, 122, 24, 0.25); stop-opacity:1" /> 
                            <stop offset="100%" style="stop-color: #ffffff; stop-opacity:1" /> 
                        </linearGradient> 
                    </defs> 
                    <rect width="350" height="60" id="' || mcoh.ID || '" fill="url(#grad' || mcoh.ID || ')"  
                          class="box" rx="8" ry="8"></rect> 
                    <text x="50%" y="50%" alignment-baseline="middle" text-anchor="middle" fill="black"  
                          font-size="16" font-family="Arial"> 
                        ' || mc.CLIENT_NAME || ' - ' || mcoh.ORG_HIERARCHY || ': ' || mcoh.HIER_NAME || ' 
                    </text> 
                    <foreignObject x="10" y="15" width="30" height="30"> 
                        <div xmlns="http://www.w3.org/1999/xhtml" style="padding: 5px;"> 
                            <i class="fa fa-edit edit-icon" data-id="' || mcoh.ID || '"  
                               style="color: #007bff; cursor: pointer;"></i> 
                        </div> 
                    </foreignObject> 
                </svg> 
                <i class="fa fa-caret-down" style="margin-left: 10px;"></i> 
            </div>' AS LABEL, 
            LEVEL AS HIERARCHY_LEVEL 
        FROM MST_CLIENT_ORG_HIER mcoh 
        JOIN MST_CLIENT mc ON mcoh.CLIENT_ID = mc.ID 
        WHERE mcoh.IS_ACTIVE = 'Y' AND (mcoh.CLIENT_ID = p_client_id OR p_client_id IS NULL) 
        START WITH mcoh.PARENT_ID IS NULL 
        CONNECT BY PRIOR mcoh.ID = mcoh.PARENT_ID 
        ORDER SIBLINGS BY mcoh.HIER_NAME 
    ) LOOP 
        -- Manage hierarchy indentation using <ul> 
        IF rec.HIERARCHY_LEVEL > l_prev_level THEN 
            l_html := l_html || '<ul style="list-style-type: none; padding-left: 20px;">'; 
        ELSIF rec.HIERARCHY_LEVEL < l_prev_level THEN 
            FOR i IN 1 .. (l_prev_level - rec.HIERARCHY_LEVEL) LOOP 
                l_html := l_html || '</ul></li>'; 
            END LOOP; 
        ELSE 
            l_html := l_html || '</li>'; 
        END IF; 
 
        -- List Item for the current node 
        l_html := l_html || '<li style="padding: 10px; border-radius: 10px; text-align: center;">'; 
        l_html := l_html || rec.LABEL; 
 
        -- Update previous level tracker 
        l_prev_level := rec.HIERARCHY_LEVEL; 
    END LOOP; 
 
    -- Close remaining open UL elements 
    FOR i IN 1..l_prev_level LOOP 
        l_html := l_html || '</li></ul>'; 
    END LOOP; 
 
    RETURN l_html; 
END FN_DYNAMIC_ORG_TREE_2;
/
create or replace function "FN_EVERY_USER" ( 
    p_user_email in varchar2 ) 
return boolean 
as 
    v_email varchar2(255) := trim(lower(p_user_email)); 
    v_count number; 
begin 
    select count(1) into v_count from MST_USERS where lower(EMAIL) = v_email; 
 
    if v_count > 0 then  
        return true; 
 
    else 
        return false; 
     
    end if; 
 
exception when others then 
        return false; 
 
end "FN_EVERY_USER";
/
create or replace FUNCTION FN_EXECUTIVE_ANALYSIS_DASHBOARD_EBS 
( 
    v_schema_name VARCHAR2, 
    p_business_process VARCHAR2, 
    p_risk_rating VARCHAR2, 
    p_sync_id NUMBER, 
    p_control_type VARCHAR2, 
    p_security_profile_flag VARCHAR2, 
    p_ou_name_leg1 VARCHAR2, 
    p_ou_name_leg2 varchar2 
) RETURN CLOB 
AS 
    l_html CLOB; 
    l_query CLOB; 
    critv_count NUMBER; 
    TYPE base_data_rec IS RECORD ( 
        NAMES VARCHAR2(100), 
        ACCESST CLOB, 
        CRITV NUMBER, 
        HIGHV NUMBER, 
        MEDIUMV NUMBER, 
        VALUE NUMBER, 
        TOTALVAL NUMBER, 
        SENSITIVE NUMBER 
    ); 
    TYPE base_data_tbl IS TABLE OF base_data_rec; 
    base_data base_data_tbl; 
BEGIN 
 
    l_html := ' 
        <div class="row"> 
            <table class="my-table" style="width:100%"> 
                <colgroup> 
                    <col style="width: auto;"> 
                    <col class="breakline"> 
                </colgroup> 
                <tr> 
                    <th class="first-column" style="font-weight: bold; font-size: 1.4rem; padding: 10px;">User Profile</th> 
                    <th></th> 
                    <th class="second-column" style="font-weight: bold; font-size: 1.4rem; padding: 10px;">Access Aspects</th>   
                    <th class="third-column" style="font-weight: bold; font-size: 1.4rem; padding: 10px;">Critical</th> 
                    <th class="fourth-column" style="font-weight: bold; font-size: 1.4rem; padding: 10px;">High</th>   
                    <th class="fifth-column" style="font-weight: bold; font-size: 1.4rem; padding: 10px;">Medium</th>   
                    <th class="sixth-column" style="font-weight: bold; font-size: 1.4rem; padding: 10px;">Total</th>   
                    <th></th> 
                    <th class="seventh-column" style="font-weight: bold; font-size: 1.4rem; padding: 10px;">Sensitive</th>   
                </tr>'; 
 
    l_query := ' 
        WITH split_values AS ( 
            SELECT REGEXP_SUBSTR(:1, ''[^~]+'', 1, LEVEL) AS BUSINESS_PROCESS FROM DUAL 
            CONNECT BY REGEXP_SUBSTR(:1, ''[^~]+'', 1, LEVEL) IS NOT NULL 
        ), 
        split_values_1 AS ( 
            SELECT REGEXP_SUBSTR(:2, ''[^~]+'', 1, LEVEL) AS RISK_RATING FROM DUAL 
            CONNECT BY REGEXP_SUBSTR(:2, ''[^~]+'', 1, LEVEL) IS NOT NULL 
        ), 
        base_data AS ( 
            SELECT ''Active'' AS NAMES, 
                ''<span class="icons-design"><span class="fa fa-archive" aria-hidden="true" style="font-weight: 1000"></span><p>Rules Consider</p></span>'' AS ACCESST, 
                -- Critical Value 
                (SELECT COUNT(DISTINCT ' || v_schema_name || '.XX_EBS_SOD_MST.ID) FROM ' || v_schema_name || '.XX_EBS_SOD_MST  
                LEFT JOIN split_values ON ' || v_schema_name || '.XX_EBS_SOD_MST.BUSINESS_PROCESS = split_values.BUSINESS_PROCESS  
                LEFT JOIN split_values_1 ON ' || v_schema_name || '.XX_EBS_SOD_MST.RISK_RATING = split_values_1.RISK_RATING  
                    WHERE ' || v_schema_name || '.XX_EBS_SOD_MST.RISK_RATING LIKE ''%Critical%''  
                    AND ' || v_schema_name || '.XX_EBS_SOD_MST.CONTROL_STATUS = ''ACTIVE'' 
                    AND (:1 IS NULL OR :1 = '''' OR split_values.BUSINESS_PROCESS IS NOT NULL)  
                    AND (:2 IS NULL OR :2 = '''' OR split_values_1.RISK_RATING IS NOT NULL) 
                    AND (:P11_SYNC_NAME IS NULL OR :P11_SYNC_NAME = '''' OR ' || v_schema_name || '.XX_EBS_SOD_MST.IRM_JOB_ID = :P11_SYNC_NAME) 
                    AND ('|| v_schema_name ||'.XX_EBS_SOD_MST.CONTROL_TYPE = :P11_CONTROL_TYPE  OR :P11_CONTROL_TYPE IS NULL)) AS CRITV, 
                -- High Value 
                (SELECT COUNT(DISTINCT ' || v_schema_name || '.XX_EBS_SOD_MST.ID) FROM ' || v_schema_name || '.XX_EBS_SOD_MST  
                LEFT JOIN split_values ON ' || v_schema_name || '.XX_EBS_SOD_MST.BUSINESS_PROCESS = split_values.BUSINESS_PROCESS  
                LEFT JOIN split_values_1 ON ' || v_schema_name || '.XX_EBS_SOD_MST.RISK_RATING = split_values_1.RISK_RATING  
                    WHERE ' || v_schema_name || '.XX_EBS_SOD_MST.RISK_RATING LIKE ''%High%''  
                    AND ' || v_schema_name || '.XX_EBS_SOD_MST.CONTROL_STATUS = ''ACTIVE'' 
                    AND (:1 IS NULL OR :1 = '''' OR split_values.BUSINESS_PROCESS IS NOT NULL)  
                    AND (:2 IS NULL OR :2 = '''' OR split_values_1.RISK_RATING IS NOT NULL) 
                    AND (:P11_SYNC_NAME IS NULL OR :P11_SYNC_NAME = '''' OR ' || v_schema_name || '.XX_EBS_SOD_MST.IRM_JOB_ID = :P11_SYNC_NAME) 
                    AND ('|| v_schema_name ||'.XX_EBS_SOD_MST.CONTROL_TYPE = :P11_CONTROL_TYPE  OR :P11_CONTROL_TYPE IS NULL)) AS HIGHV, 
                -- Medium Value 
                (SELECT COUNT(DISTINCT ' || v_schema_name || '.XX_EBS_SOD_MST.ID) FROM ' || v_schema_name || '.XX_EBS_SOD_MST  
                LEFT JOIN split_values ON ' || v_schema_name || '.XX_EBS_SOD_MST.BUSINESS_PROCESS = split_values.BUSINESS_PROCESS  
                LEFT JOIN split_values_1 ON ' || v_schema_name || '.XX_EBS_SOD_MST.RISK_RATING = split_values_1.RISK_RATING  
                    WHERE ' || v_schema_name || '.XX_EBS_SOD_MST.RISK_RATING LIKE ''%Medium%'' 
                    AND ' || v_schema_name || '.XX_EBS_SOD_MST.CONTROL_STATUS = ''ACTIVE''  
                    AND (:1 IS NULL OR :1 = '''' OR split_values.BUSINESS_PROCESS IS NOT NULL)  
                    AND (:2 IS NULL OR :2 = '''' OR split_values_1.RISK_RATING IS NOT NULL) 
                    AND (:P11_SYNC_NAME IS NULL OR :P11_SYNC_NAME = '''' OR ' || v_schema_name || '.XX_EBS_SOD_MST.IRM_JOB_ID = :P11_SYNC_NAME) 
                    AND ('|| v_schema_name ||'.XX_EBS_SOD_MST.CONTROL_TYPE = :P11_CONTROL_TYPE  OR :P11_CONTROL_TYPE IS NULL)) AS MEDIUMV, 
                -- Value 
                (SELECT COUNT(DISTINCT ' || v_schema_name || '.XX_EBS_SOD_USERS.USER_ID) FROM ' || v_schema_name || '.XX_EBS_SOD_USERS 
                WHERE (:P11_SYNC_NAME IS NULL OR :P11_SYNC_NAME = '''' OR ' || v_schema_name || '.XX_EBS_SOD_USERS.IRM_JOB_ID = :P11_SYNC_NAME)) AS VALUE, 
                -- Total Value 
                (SELECT  
                    COUNT(DISTINCT CASE WHEN ' || v_schema_name || '.XX_EBS_SOD_MST.RISK_RATING LIKE ''%Critical%'' THEN ' || v_schema_name || '.XX_EBS_SOD_MST.ID END) + 
                    COUNT(DISTINCT CASE WHEN ' || v_schema_name || '.XX_EBS_SOD_MST.RISK_RATING LIKE ''%High%'' THEN ' || v_schema_name || '.XX_EBS_SOD_MST.ID END) + 
                    COUNT(DISTINCT CASE WHEN ' || v_schema_name || '.XX_EBS_SOD_MST.RISK_RATING LIKE ''%Medium%'' THEN ' || v_schema_name || '.XX_EBS_SOD_MST.ID END) AS TOTALVAL 
                FROM ' || v_schema_name || '.XX_EBS_SOD_MST 
                LEFT JOIN split_values ON ' || v_schema_name || '.XX_EBS_SOD_MST.BUSINESS_PROCESS = split_values.BUSINESS_PROCESS 
                LEFT JOIN split_values_1 ON ' || v_schema_name || '.XX_EBS_SOD_MST.RISK_RATING = split_values_1.RISK_RATING 
                WHERE ' || v_schema_name || '.XX_EBS_SOD_MST.CONTROL_STATUS = ''ACTIVE'' 
                    AND (:1 IS NULL OR :1 = '''' OR split_values.BUSINESS_PROCESS IS NOT NULL) 
                    AND (:2 IS NULL OR :2 = '''' OR split_values_1.RISK_RATING IS NOT NULL) 
                    AND (:P11_SYNC_NAME IS NULL OR :P11_SYNC_NAME = '''' OR ' || v_schema_name || '.XX_EBS_SOD_MST.IRM_JOB_ID = :P11_SYNC_NAME) 
                    AND ('|| v_schema_name ||'.XX_EBS_SOD_MST.CONTROL_TYPE = :P11_CONTROL_TYPE  OR :P11_CONTROL_TYPE IS NULL) 
                ) AS TOTALVAL, 
                -- Sensitive Value 
                (SELECT COUNT(DISTINCT ' || v_schema_name || '.XX_EBS_SOD_MST.ID) FROM ' || v_schema_name || '.XX_EBS_SOD_MST LEFT JOIN split_values ON ' || v_schema_name || '.XX_EBS_SOD_MST.BUSINESS_PROCESS = split_values.BUSINESS_PROCESS LEFT JOIN split_values_1 ON ' || v_schema_name || '.XX_EBS_SOD_MST.RISK_RATING = split_values_1.RISK_RATING WHERE ' || v_schema_name || '.XX_EBS_SOD_MST.RISK_RATING LIKE ''%Sensitive%'' AND (:1 IS NULL OR :1 = '''' OR split_values.BUSINESS_PROCESS IS NOT NULL) AND (:2 IS NULL OR :2 = '''' OR split_values_1.RISK_RATING IS NOT NULL) 
                AND (:P11_SYNC_NAME IS NULL OR :P11_SYNC_NAME = '''' OR ' || v_schema_name || '.XX_EBS_SOD_MST.IRM_JOB_ID = :P11_SYNC_NAME) 
                AND ('|| v_schema_name ||'.XX_EBS_SOD_MST.CONTROL_TYPE = :P11_CONTROL_TYPE  OR :P11_CONTROL_TYPE IS NULL)) AS SENSITIVE 
            FROM DUAL 
 
            UNION ALL 
 
            SELECT ''Employees'' AS NAMES, 
                ''<span class="icons-design"><span aria-hidden="true" class="fa fa-database-x" style="font-weight: 1000"></span><p>Rules Violated</p></span>'' AS ACCESST, 
                -- Critical Value 
                (SELECT COUNT(DISTINCT ' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE.CONTROL_ID) FROM ' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE  
                INNER JOIN ' || v_schema_name || '.XX_EBS_SOD_MST ON ' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE.CONTROL_ID = ' || v_schema_name || '.XX_EBS_SOD_MST.ID  
                LEFT JOIN split_values ON ' || v_schema_name || '.XX_EBS_SOD_MST.BUSINESS_PROCESS = split_values.BUSINESS_PROCESS  
                LEFT JOIN split_values_1 ON ' || v_schema_name || '.XX_EBS_SOD_MST.RISK_RATING = split_values_1.RISK_RATING  
                    WHERE ' || v_schema_name || '.XX_EBS_SOD_MST.RISK_RATING LIKE ''%Critical%''  
                    AND (:1 IS NULL OR :1 = '''' OR split_values.BUSINESS_PROCESS IS NOT NULL)  
                    AND (:2 IS NULL OR :2 = '''' OR split_values_1.RISK_RATING IS NOT NULL) 
                    AND (:P11_SYNC_NAME IS NULL OR :P11_SYNC_NAME = '''' OR ' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE.IRM_JOB_ID = :P11_SYNC_NAME) 
                    AND ('|| v_schema_name ||'.XX_EBS_SOD_MST.CONTROL_TYPE = :P11_CONTROL_TYPE  OR :P11_CONTROL_TYPE IS NULL) 
                    AND ('|| v_schema_name ||'.TRN_CONTROL_SECURITY_PROFILE.IS_FALSE_POSITIVE = :P11_CONSIDER_SECURITY_PROFILE  OR :P11_CONSIDER_SECURITY_PROFILE IS NULL) 
                    AND ('|| v_schema_name ||'.TRN_CONTROL_SECURITY_PROFILE.ENT_LEG1_INCLUDE_ORGANIZATION_NAME = :P11_LEG1_OU_NAME OR :P11_LEG1_OU_NAME IS NULL) 
                    AND ('|| v_schema_name ||'.TRN_CONTROL_SECURITY_PROFILE.ENT_LEG2_INCLUDE_ORGANIZATION_NAME = :P11_LEG2_OU_NAME OR :P11_LEG2_OU_NAME IS NULL)) AS CRITV, 
                -- High Value 
                (SELECT COUNT(DISTINCT ' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE.CONTROL_ID) FROM ' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE  
                INNER JOIN ' || v_schema_name || '.XX_EBS_SOD_MST ON ' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE.CONTROL_ID = ' || v_schema_name || '.XX_EBS_SOD_MST.ID  
                LEFT JOIN split_values ON ' || v_schema_name || '.XX_EBS_SOD_MST.BUSINESS_PROCESS = split_values.BUSINESS_PROCESS  
                LEFT JOIN split_values_1 ON ' || v_schema_name || '.XX_EBS_SOD_MST.RISK_RATING = split_values_1.RISK_RATING  
                    WHERE ' || v_schema_name || '.XX_EBS_SOD_MST.RISK_RATING LIKE ''%High%''  
                    AND (:1 IS NULL OR :1 = '''' OR split_values.BUSINESS_PROCESS IS NOT NULL)  
                    AND (:2 IS NULL OR :2 = '''' OR split_values_1.RISK_RATING IS NOT NULL) 
                    AND (:P11_SYNC_NAME IS NULL OR :P11_SYNC_NAME = '''' OR ' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE.IRM_JOB_ID = :P11_SYNC_NAME) 
                    AND ('|| v_schema_name ||'.XX_EBS_SOD_MST.CONTROL_TYPE = :P11_CONTROL_TYPE  OR :P11_CONTROL_TYPE IS NULL) 
                    AND ('|| v_schema_name ||'.TRN_CONTROL_SECURITY_PROFILE.IS_FALSE_POSITIVE = :P11_CONSIDER_SECURITY_PROFILE  OR :P11_CONSIDER_SECURITY_PROFILE IS NULL) 
                    AND ('|| v_schema_name ||'.TRN_CONTROL_SECURITY_PROFILE.ENT_LEG1_INCLUDE_ORGANIZATION_NAME = :P11_LEG1_OU_NAME OR :P11_LEG1_OU_NAME IS NULL) 
                    AND ('|| v_schema_name ||'.TRN_CONTROL_SECURITY_PROFILE.ENT_LEG2_INCLUDE_ORGANIZATION_NAME = :P11_LEG2_OU_NAME OR :P11_LEG2_OU_NAME IS NULL)) AS HIGHV, 
                -- Medium Value 
                (SELECT COUNT(DISTINCT ' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE.CONTROL_ID) FROM ' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE INNER JOIN ' || v_schema_name || '.XX_EBS_SOD_MST ON ' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE.CONTROL_ID = ' || v_schema_name || '.XX_EBS_SOD_MST.ID LEFT JOIN split_values ON ' || v_schema_name || '.XX_EBS_SOD_MST.BUSINESS_PROCESS = split_values.BUSINESS_PROCESS LEFT JOIN split_values_1 ON ' || v_schema_name || '.XX_EBS_SOD_MST.RISK_RATING = split_values_1.RISK_RATING WHERE ' || v_schema_name || '.XX_EBS_SOD_MST.RISK_RATING LIKE ''%Medium%'' AND (:1 IS NULL OR :1 = '''' OR split_values.BUSINESS_PROCESS IS NOT NULL) AND (:2 IS NULL OR :2 = '''' OR split_values_1.RISK_RATING IS NOT NULL) 
                AND (:P11_SYNC_NAME IS NULL OR :P11_SYNC_NAME = '''' OR ' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE.IRM_JOB_ID = :P11_SYNC_NAME) 
                AND ('|| v_schema_name ||'.XX_EBS_SOD_MST.CONTROL_TYPE = :P11_CONTROL_TYPE  OR :P11_CONTROL_TYPE IS NULL) 
                AND ('|| v_schema_name ||'.TRN_CONTROL_SECURITY_PROFILE.IS_FALSE_POSITIVE = :P11_CONSIDER_SECURITY_PROFILE  OR :P11_CONSIDER_SECURITY_PROFILE IS NULL) 
                AND ('|| v_schema_name ||'.TRN_CONTROL_SECURITY_PROFILE.ENT_LEG1_INCLUDE_ORGANIZATION_NAME = :P11_LEG1_OU_NAME OR :P11_LEG1_OU_NAME IS NULL) 
                AND ('|| v_schema_name ||'.TRN_CONTROL_SECURITY_PROFILE.ENT_LEG2_INCLUDE_ORGANIZATION_NAME = :P11_LEG2_OU_NAME OR :P11_LEG2_OU_NAME IS NULL)) AS MEDIUMV, 
                -- Value 
                (SELECT count(user_id) FROM ' || v_schema_name || '.XX_EBS_SOD_USERS 
                WHERE (:P11_SYNC_NAME IS NULL OR :P11_SYNC_NAME = '''' OR ' || v_schema_name || '.XX_EBS_SOD_USERS.IRM_JOB_ID = :P11_SYNC_NAME)) AS VALUE, 
                -- Total Value 
                (SELECT  
                    COUNT(DISTINCT CASE WHEN ' || v_schema_name || '.XX_EBS_SOD_MST.RISK_RATING LIKE ''%Critical%'' THEN ' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE.CONTROL_ID END) + 
                    COUNT(DISTINCT CASE WHEN ' || v_schema_name || '.XX_EBS_SOD_MST.RISK_RATING LIKE ''%High%'' THEN ' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE.CONTROL_ID END) + 
                    COUNT(DISTINCT CASE WHEN ' || v_schema_name || '.XX_EBS_SOD_MST.RISK_RATING LIKE ''%Medium%'' THEN ' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE.CONTROL_ID END) 
                FROM ' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE  
                INNER JOIN ' || v_schema_name || '.XX_EBS_SOD_MST ON ' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE.CONTROL_ID = ' || v_schema_name || '.XX_EBS_SOD_MST.ID 
                LEFT JOIN split_values ON ' || v_schema_name || '.XX_EBS_SOD_MST.BUSINESS_PROCESS = split_values.BUSINESS_PROCESS  
                LEFT JOIN split_values_1 ON ' || v_schema_name || '.XX_EBS_SOD_MST.RISK_RATING = split_values_1.RISK_RATING 
                WHERE (:1 IS NULL OR :1 = '''' OR split_values.BUSINESS_PROCESS IS NOT NULL) 
                AND (:2 IS NULL OR :2 = '''' OR split_values_1.RISK_RATING IS NOT NULL) 
                AND (:P11_SYNC_NAME IS NULL OR :P11_SYNC_NAME = '''' OR ' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE.IRM_JOB_ID = :P11_SYNC_NAME) 
                AND ('|| v_schema_name ||'.XX_EBS_SOD_MST.CONTROL_TYPE = :P11_CONTROL_TYPE  OR :P11_CONTROL_TYPE IS NULL) 
                AND ('|| v_schema_name ||'.TRN_CONTROL_SECURITY_PROFILE.IS_FALSE_POSITIVE = :P11_CONSIDER_SECURITY_PROFILE  OR :P11_CONSIDER_SECURITY_PROFILE IS NULL) 
                AND ('|| v_schema_name ||'.TRN_CONTROL_SECURITY_PROFILE.ENT_LEG1_INCLUDE_ORGANIZATION_NAME = :P11_LEG1_OU_NAME OR :P11_LEG1_OU_NAME IS NULL) 
                AND ('|| v_schema_name ||'.TRN_CONTROL_SECURITY_PROFILE.ENT_LEG2_INCLUDE_ORGANIZATION_NAME = :P11_LEG2_OU_NAME OR :P11_LEG2_OU_NAME IS NULL)) AS TOTALVAL, 
                -- Sensitive Value 
                (SELECT COUNT(DISTINCT ' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE.CONTROL_ID) FROM ' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE INNER JOIN ' || v_schema_name || '.XX_EBS_SOD_MST ON ' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE.CONTROL_ID = ' || v_schema_name || '.XX_EBS_SOD_MST.ID LEFT JOIN split_values ON ' || v_schema_name || '.XX_EBS_SOD_MST.BUSINESS_PROCESS = split_values.BUSINESS_PROCESS LEFT JOIN split_values_1 ON ' || v_schema_name || '.XX_EBS_SOD_MST.RISK_RATING = split_values_1.RISK_RATING WHERE ' || v_schema_name || '.XX_EBS_SOD_MST.RISK_RATING LIKE ''%Sensitive%'' AND (:1 IS NULL OR :1 = '''' OR split_values.BUSINESS_PROCESS IS NOT NULL) AND (:2 IS NULL OR :2 = '''' OR split_values_1.RISK_RATING IS NOT NULL) 
                AND (:P11_SYNC_NAME IS NULL OR :P11_SYNC_NAME = '''' OR ' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE.IRM_JOB_ID = :P11_SYNC_NAME) 
                AND ('|| v_schema_name ||'.XX_EBS_SOD_MST.CONTROL_TYPE = :P11_CONTROL_TYPE  OR :P11_CONTROL_TYPE IS NULL) 
                AND ('|| v_schema_name ||'.TRN_CONTROL_SECURITY_PROFILE.IS_FALSE_POSITIVE = :P11_CONSIDER_SECURITY_PROFILE  OR :P11_CONSIDER_SECURITY_PROFILE IS NULL) 
                AND ('|| v_schema_name ||'.TRN_CONTROL_SECURITY_PROFILE.ENT_LEG1_INCLUDE_ORGANIZATION_NAME = :P11_LEG1_OU_NAME   
                OR :P11_LEG1_OU_NAME IS NULL) 
                AND ('|| v_schema_name ||'.TRN_CONTROL_SECURITY_PROFILE.ENT_LEG2_INCLUDE_ORGANIZATION_NAME = :P11_LEG2_OU_NAME   
                OR :P11_LEG2_OU_NAME IS NULL)) AS SENSITIVE 
            FROM DUAL 
 
            UNION ALL 
 
            SELECT ''Partners'' AS NAMES, 
                ''<span class="icons-design"><span aria-hidden="true" class="fa fa-database-x" style="font-weight: 1000"></span><p>Unique Users with Instances</p></span>'' AS ACCESST, 
                -- Critical Value 
                (SELECT COUNT(DISTINCT ' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE.USER_ID) FROM ' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE INNER JOIN ' || v_schema_name || '.XX_EBS_SOD_USERS ON ' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE.USER_ID = ' || v_schema_name || '.XX_EBS_SOD_USERS.USER_ID INNER JOIN ' || v_schema_name || '.XX_EBS_SOD_MST ON ' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE.CONTROL_ID = ' || v_schema_name || '.XX_EBS_SOD_MST.ID LEFT JOIN split_values ON ' || v_schema_name || '.XX_EBS_SOD_MST.BUSINESS_PROCESS = split_values.BUSINESS_PROCESS LEFT JOIN split_values_1 ON ' || v_schema_name || '.XX_EBS_SOD_MST.RISK_RATING = split_values_1.RISK_RATING WHERE ' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE.USER_ID NOT IN (SELECT USER_ID FROM ' || v_schema_name || '.XX_EBS_SOD_USER_EXCLUSION WHERE IS_EXCLUDED = ''Y'') 
                AND ' || v_schema_name || '.XX_EBS_SOD_MST.RISK_RATING LIKE ''%Critical%'' AND (:1 IS NULL OR :1 = '''' OR split_values.BUSINESS_PROCESS IS NOT NULL) AND (:2 IS NULL OR :2 = '''' OR split_values_1.RISK_RATING IS NOT NULL) 
                AND (:P11_SYNC_NAME IS NULL OR :P11_SYNC_NAME = '''' OR ' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE.IRM_JOB_ID = :P11_SYNC_NAME) 
                AND ('|| v_schema_name ||'.XX_EBS_SOD_MST.CONTROL_TYPE = :P11_CONTROL_TYPE  OR :P11_CONTROL_TYPE IS NULL) 
                AND ('|| v_schema_name ||'.TRN_CONTROL_SECURITY_PROFILE.IS_FALSE_POSITIVE = :P11_CONSIDER_SECURITY_PROFILE  OR :P11_CONSIDER_SECURITY_PROFILE IS NULL) 
                AND ('|| v_schema_name ||'.TRN_CONTROL_SECURITY_PROFILE.ENT_LEG1_INCLUDE_ORGANIZATION_NAME = :P11_LEG1_OU_NAME   
                OR :P11_LEG1_OU_NAME IS NULL) 
                AND ('|| v_schema_name ||'.TRN_CONTROL_SECURITY_PROFILE.ENT_LEG2_INCLUDE_ORGANIZATION_NAME = :P11_LEG2_OU_NAME   
                OR :P11_LEG2_OU_NAME IS NULL)) AS CRITV, 
                -- High Value 
                (SELECT COUNT(DISTINCT ' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE.USER_ID) FROM ' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE INNER JOIN ' || v_schema_name || '.XX_EBS_SOD_USERS ON ' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE.USER_ID = ' || v_schema_name || '.XX_EBS_SOD_USERS.USER_ID INNER JOIN ' || v_schema_name || '.XX_EBS_SOD_MST ON ' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE.CONTROL_ID = ' || v_schema_name || '.XX_EBS_SOD_MST.ID LEFT JOIN split_values ON ' || v_schema_name || '.XX_EBS_SOD_MST.BUSINESS_PROCESS = split_values.BUSINESS_PROCESS LEFT JOIN split_values_1 ON ' || v_schema_name || '.XX_EBS_SOD_MST.RISK_RATING = split_values_1.RISK_RATING WHERE ' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE.USER_ID NOT IN (SELECT USER_ID FROM ' || v_schema_name || '.XX_EBS_SOD_USER_EXCLUSION WHERE IS_EXCLUDED = ''Y'') 
                AND ' || v_schema_name || '.XX_EBS_SOD_MST.RISK_RATING LIKE ''%High%'' AND (:1 IS NULL OR :1 = '''' OR split_values.BUSINESS_PROCESS IS NOT NULL) AND (:2 IS NULL OR :2 = '''' OR split_values_1.RISK_RATING IS NOT NULL) 
                AND (:P11_SYNC_NAME IS NULL OR :P11_SYNC_NAME = '''' OR ' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE.IRM_JOB_ID = :P11_SYNC_NAME) 
                AND ('|| v_schema_name ||'.XX_EBS_SOD_MST.CONTROL_TYPE = :P11_CONTROL_TYPE  OR :P11_CONTROL_TYPE IS NULL) 
                AND ('|| v_schema_name ||'.TRN_CONTROL_SECURITY_PROFILE.IS_FALSE_POSITIVE = :P11_CONSIDER_SECURITY_PROFILE  OR :P11_CONSIDER_SECURITY_PROFILE IS NULL) 
                AND ('|| v_schema_name ||'.TRN_CONTROL_SECURITY_PROFILE.ENT_LEG1_INCLUDE_ORGANIZATION_NAME = :P11_LEG1_OU_NAME   
                OR :P11_LEG1_OU_NAME IS NULL) 
                AND ('|| v_schema_name ||'.TRN_CONTROL_SECURITY_PROFILE.ENT_LEG2_INCLUDE_ORGANIZATION_NAME = :P11_LEG2_OU_NAME   
                OR :P11_LEG2_OU_NAME IS NULL)) AS HIGHV, 
                -- Medium Value 
                (SELECT COUNT(DISTINCT ' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE.USER_ID) FROM ' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE INNER JOIN ' || v_schema_name || '.XX_EBS_SOD_USERS ON ' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE.USER_ID = ' || v_schema_name || '.XX_EBS_SOD_USERS.USER_ID INNER JOIN ' || v_schema_name || '.XX_EBS_SOD_MST ON ' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE.CONTROL_ID = ' || v_schema_name || '.XX_EBS_SOD_MST.ID LEFT JOIN split_values ON ' || v_schema_name || '.XX_EBS_SOD_MST.BUSINESS_PROCESS = split_values.BUSINESS_PROCESS LEFT JOIN split_values_1 ON ' || v_schema_name || '.XX_EBS_SOD_MST.RISK_RATING = split_values_1.RISK_RATING WHERE ' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE.USER_ID NOT IN (SELECT USER_ID FROM ' || v_schema_name || '.XX_EBS_SOD_USER_EXCLUSION WHERE IS_EXCLUDED = ''Y'') 
                AND ' || v_schema_name || '.XX_EBS_SOD_MST.RISK_RATING LIKE ''%Medium%'' AND (:1 IS NULL OR :1 = '''' OR split_values.BUSINESS_PROCESS IS NOT NULL) AND (:2 IS NULL OR :2 = '''' OR split_values_1.RISK_RATING IS NOT NULL) 
                AND (:P11_SYNC_NAME IS NULL OR :P11_SYNC_NAME = '''' OR ' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE.IRM_JOB_ID = :P11_SYNC_NAME) 
                AND ('|| v_schema_name ||'.XX_EBS_SOD_MST.CONTROL_TYPE = :P11_CONTROL_TYPE  OR :P11_CONTROL_TYPE IS NULL) 
                AND ('|| v_schema_name ||'.TRN_CONTROL_SECURITY_PROFILE.IS_FALSE_POSITIVE = :P11_CONSIDER_SECURITY_PROFILE  OR :P11_CONSIDER_SECURITY_PROFILE IS NULL) 
                AND ('|| v_schema_name ||'.TRN_CONTROL_SECURITY_PROFILE.ENT_LEG1_INCLUDE_ORGANIZATION_NAME = :P11_LEG1_OU_NAME   
                OR :P11_LEG1_OU_NAME IS NULL) 
                AND ('|| v_schema_name ||'.TRN_CONTROL_SECURITY_PROFILE.ENT_LEG2_INCLUDE_ORGANIZATION_NAME = :P11_LEG2_OU_NAME OR :P11_LEG2_OU_NAME IS NULL)) AS LOWV, 
                -- Value 
                (SELECT COUNT(DISTINCT ' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE.USER_ID) FROM ' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE INNER JOIN ' || v_schema_name || '.XX_EBS_SOD_USERS ON ' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE.USER_ID = ' || v_schema_name || '.XX_EBS_SOD_USERS.USER_ID INNER JOIN ' || v_schema_name || '.XX_EBS_SOD_MST ON ' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE.CONTROL_ID = ' || v_schema_name || '.XX_EBS_SOD_MST.ID WHERE ' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE.USER_ID NOT IN (SELECT USER_ID FROM ' || v_schema_name || '.XX_EBS_SOD_USER_EXCLUSION WHERE IS_EXCLUDED = ''Y'') 
                AND (:P11_SYNC_NAME IS NULL OR :P11_SYNC_NAME = '''' OR ' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE.IRM_JOB_ID = :P11_SYNC_NAME) 
                AND ' || v_schema_name || '.XX_EBS_SOD_MST.CONTROL_TYPE LIKE ''%SOD%'' 
                -- AND ('|| v_schema_name ||'.XX_EBS_SOD_MST.CONTROL_TYPE = :P11_CONTROL_TYPE  OR :P11_CONTROL_TYPE IS NULL) 
                AND ('|| v_schema_name ||'.TRN_CONTROL_SECURITY_PROFILE.IS_FALSE_POSITIVE = :P11_CONSIDER_SECURITY_PROFILE  OR :P11_CONSIDER_SECURITY_PROFILE IS NULL) 
                AND ('|| v_schema_name ||'.TRN_CONTROL_SECURITY_PROFILE.ENT_LEG1_INCLUDE_ORGANIZATION_NAME = :P11_LEG1_OU_NAME   
                OR :P11_LEG1_OU_NAME IS NULL) 
                AND ('|| v_schema_name ||'.TRN_CONTROL_SECURITY_PROFILE.ENT_LEG2_INCLUDE_ORGANIZATION_NAME = :P11_LEG2_OU_NAME OR :P11_LEG2_OU_NAME IS NULL)) AS VALUE, 
                -- Total Value 
                (SELECT COUNT(DISTINCT USER_ID)  
                FROM ' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE out_irm 
                INNER JOIN ' || v_schema_name || '.XX_EBS_SOD_MST mst  
                    ON out_irm.CONTROL_ID = mst.ID 
                LEFT JOIN split_values  
                    ON mst.BUSINESS_PROCESS = split_values.BUSINESS_PROCESS 
                LEFT JOIN split_values_1  
                    ON mst.RISK_RATING = split_values_1.RISK_RATING 
                WHERE out_irm.USER_ID NOT IN (SELECT USER_ID FROM ' || v_schema_name || '.XX_EBS_SOD_USER_EXCLUSION WHERE IS_EXCLUDED = ''Y'') 
                AND mst.RISK_RATING IN (''%Critical%'', ''High'', ''Medium'') 
                    AND (:1 IS NULL OR :1 = ''''  
                        OR split_values.BUSINESS_PROCESS IS NOT NULL) 
                    AND (:2 IS NULL OR :2 = ''''  
                        OR split_values_1.RISK_RATING IS NOT NULL) 
                    AND (:P11_SYNC_NAME IS NULL OR :P11_SYNC_NAME = ''''  
                        OR out_irm.IRM_JOB_ID = :P11_SYNC_NAME) 
                    AND (mst.CONTROL_TYPE = :P11_CONTROL_TYPE  OR :P11_CONTROL_TYPE IS NULL) 
                    AND (out_irm.IS_FALSE_POSITIVE = :P11_CONSIDER_SECURITY_PROFILE  OR :P11_CONSIDER_SECURITY_PROFILE IS NULL) 
                    AND (out_irm.ENT_LEG1_INCLUDE_ORGANIZATION_NAME = :P11_LEG1_OU_NAME OR :P11_LEG1_OU_NAME IS NULL) 
                    AND (out_irm.ENT_LEG2_INCLUDE_ORGANIZATION_NAME = :P11_LEG2_OU_NAME OR :P11_LEG2_OU_NAME IS NULL) 
                ) AS TOTALVAL, 
                -- Sensitive Value 
                (SELECT COUNT(DISTINCT ' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE.USER_ID) FROM ' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE INNER JOIN ' || v_schema_name || '.XX_EBS_SOD_USERS ON ' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE.USER_ID = ' || v_schema_name || '.XX_EBS_SOD_USERS.USER_ID INNER JOIN ' || v_schema_name || '.XX_EBS_SOD_MST ON ' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE.ID = ' || v_schema_name || '.XX_EBS_SOD_MST.ID LEFT JOIN split_values ON ' || v_schema_name || '.XX_EBS_SOD_MST.BUSINESS_PROCESS = split_values.BUSINESS_PROCESS LEFT JOIN split_values_1 ON ' || v_schema_name || '.XX_EBS_SOD_MST.RISK_RATING = split_values_1.RISK_RATING WHERE ' || v_schema_name || '.XX_EBS_SOD_MST.RISK_RATING LIKE ''%Sensitive%'' AND (:1 IS NULL OR :1 = '''' OR split_values.BUSINESS_PROCESS IS NOT NULL) AND (:2 IS NULL OR :2 = '''' OR split_values_1.RISK_RATING IS NOT NULL) 
                AND (:P11_SYNC_NAME IS NULL OR :P11_SYNC_NAME = '''' OR ' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE.IRM_JOB_ID = :P11_SYNC_NAME) 
                AND ('|| v_schema_name ||'.XX_EBS_SOD_MST.CONTROL_TYPE = :P11_CONTROL_TYPE  OR :P11_CONTROL_TYPE IS NULL) 
                AND ('|| v_schema_name ||'.TRN_CONTROL_SECURITY_PROFILE.IS_FALSE_POSITIVE = :P11_CONSIDER_SECURITY_PROFILE  OR :P11_CONSIDER_SECURITY_PROFILE IS NULL) 
                AND ('|| v_schema_name ||'.TRN_CONTROL_SECURITY_PROFILE.ENT_LEG1_INCLUDE_ORGANIZATION_NAME = :P11_LEG1_OU_NAME OR :P11_LEG1_OU_NAME IS NULL) 
                AND ('|| v_schema_name ||'.TRN_CONTROL_SECURITY_PROFILE.ENT_LEG2_INCLUDE_ORGANIZATION_NAME = :P11_LEG2_OU_NAME OR :P11_LEG2_OU_NAME IS NULL)) AS SENSITIVE 
            FROM DUAL 
 
            UNION ALL 
 
            SELECT ''Assigned Roles'' AS NAMES, 
                ''<span class="icons-design"><span aria-hidden="true" class="fa fa-abacus" style="font-weight: 1000"></span><p>Count Of Instances</p></span>'' AS ACCESST, 
                -- Critical Value 
                (SELECT COUNT(' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE.ID) FROM ' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE INNER JOIN ' || v_schema_name || '.XX_EBS_SOD_MST ON ' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE.CONTROL_ID = ' || v_schema_name || '.XX_EBS_SOD_MST.ID LEFT JOIN split_values ON ' || v_schema_name || '.XX_EBS_SOD_MST.BUSINESS_PROCESS = split_values.BUSINESS_PROCESS LEFT JOIN split_values_1 ON ' || v_schema_name || '.XX_EBS_SOD_MST.RISK_RATING = split_values_1.RISK_RATING WHERE ' || v_schema_name || '.XX_EBS_SOD_MST.RISK_RATING LIKE ''%Critical%'' AND (:1 IS NULL OR :1 = '''' OR split_values.BUSINESS_PROCESS IS NOT NULL) AND (:2 IS NULL OR :2 = '''' OR split_values_1.RISK_RATING IS NOT NULL) 
                AND (:P11_SYNC_NAME IS NULL OR :P11_SYNC_NAME = '''' OR ' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE.IRM_JOB_ID = :P11_SYNC_NAME) 
                AND ('|| v_schema_name ||'.XX_EBS_SOD_MST.CONTROL_TYPE = :P11_CONTROL_TYPE  OR :P11_CONTROL_TYPE IS NULL) 
                AND ('|| v_schema_name ||'.TRN_CONTROL_SECURITY_PROFILE.IS_FALSE_POSITIVE = :P11_CONSIDER_SECURITY_PROFILE  OR :P11_CONSIDER_SECURITY_PROFILE IS NULL) 
                AND ('|| v_schema_name ||'.TRN_CONTROL_SECURITY_PROFILE.ENT_LEG1_INCLUDE_ORGANIZATION_NAME = :P11_LEG1_OU_NAME   
                OR :P11_LEG1_OU_NAME IS NULL) 
                AND ('|| v_schema_name ||'.TRN_CONTROL_SECURITY_PROFILE.ENT_LEG2_INCLUDE_ORGANIZATION_NAME = :P11_LEG2_OU_NAME   
                OR :P11_LEG2_OU_NAME IS NULL)) AS CRITV, 
                -- High Value 
                (SELECT COUNT(' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE.ID) FROM ' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE INNER JOIN ' || v_schema_name || '.XX_EBS_SOD_MST ON ' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE.CONTROL_ID = ' || v_schema_name || '.XX_EBS_SOD_MST.ID LEFT JOIN split_values ON ' || v_schema_name || '.XX_EBS_SOD_MST.BUSINESS_PROCESS = split_values.BUSINESS_PROCESS LEFT JOIN split_values_1 ON ' || v_schema_name || '.XX_EBS_SOD_MST.RISK_RATING = split_values_1.RISK_RATING WHERE ' || v_schema_name || '.XX_EBS_SOD_MST.RISK_RATING LIKE ''%High%'' AND (:1 IS NULL OR :1 = '''' OR split_values.BUSINESS_PROCESS IS NOT NULL) AND (:2 IS NULL OR :2 = '''' OR split_values_1.RISK_RATING IS NOT NULL) 
                AND (:P11_SYNC_NAME IS NULL OR :P11_SYNC_NAME = '''' OR ' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE.IRM_JOB_ID = :P11_SYNC_NAME) 
                AND ('|| v_schema_name ||'.XX_EBS_SOD_MST.CONTROL_TYPE = :P11_CONTROL_TYPE  OR :P11_CONTROL_TYPE IS NULL) 
                AND ('|| v_schema_name ||'.TRN_CONTROL_SECURITY_PROFILE.IS_FALSE_POSITIVE = :P11_CONSIDER_SECURITY_PROFILE  OR :P11_CONSIDER_SECURITY_PROFILE IS NULL) 
                AND ('|| v_schema_name ||'.TRN_CONTROL_SECURITY_PROFILE.ENT_LEG1_INCLUDE_ORGANIZATION_NAME = :P11_LEG1_OU_NAME   
                OR :P11_LEG1_OU_NAME IS NULL) 
                AND ('|| v_schema_name ||'.TRN_CONTROL_SECURITY_PROFILE.ENT_LEG2_INCLUDE_ORGANIZATION_NAME = :P11_LEG2_OU_NAME   
                OR :P11_LEG2_OU_NAME IS NULL)) AS HIGHV, 
                -- Medium Value 
                (SELECT COUNT(' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE.ID) FROM ' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE INNER JOIN ' || v_schema_name || '.XX_EBS_SOD_MST ON ' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE.CONTROL_ID = ' || v_schema_name || '.XX_EBS_SOD_MST.ID LEFT JOIN split_values ON ' || v_schema_name || '.XX_EBS_SOD_MST.BUSINESS_PROCESS = split_values.BUSINESS_PROCESS LEFT JOIN split_values_1 ON ' || v_schema_name || '.XX_EBS_SOD_MST.RISK_RATING = split_values_1.RISK_RATING WHERE ' || v_schema_name || '.XX_EBS_SOD_MST.RISK_RATING LIKE ''%Medium%'' AND (:1 IS NULL OR :1 = '''' OR split_values.BUSINESS_PROCESS IS NOT NULL) AND (:2 IS NULL OR :2 = '''' OR split_values_1.RISK_RATING IS NOT NULL) 
                AND (:P11_SYNC_NAME IS NULL OR :P11_SYNC_NAME = '''' OR ' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE.IRM_JOB_ID = :P11_SYNC_NAME) 
                AND ('|| v_schema_name ||'.XX_EBS_SOD_MST.CONTROL_TYPE = :P11_CONTROL_TYPE  OR :P11_CONTROL_TYPE IS NULL) 
                AND ('|| v_schema_name ||'.TRN_CONTROL_SECURITY_PROFILE.IS_FALSE_POSITIVE = :P11_CONSIDER_SECURITY_PROFILE  OR :P11_CONSIDER_SECURITY_PROFILE IS NULL) 
                AND ('|| v_schema_name ||'.TRN_CONTROL_SECURITY_PROFILE.ENT_LEG1_INCLUDE_ORGANIZATION_NAME = :P11_LEG1_OU_NAME   
                OR :P11_LEG1_OU_NAME IS NULL) 
                AND ('|| v_schema_name ||'.TRN_CONTROL_SECURITY_PROFILE.ENT_LEG2_INCLUDE_ORGANIZATION_NAME = :P11_LEG2_OU_NAME   
                OR :P11_LEG2_OU_NAME IS NULL)) AS LOWV, 
                -- Value 
                (SELECT COUNT(resp_id) FROM ' || v_schema_name || '.XX_EBS_SOD_RESPONSIBILITIES 
                WHERE (:P11_SYNC_NAME IS NULL OR :P11_SYNC_NAME = '''' OR ' || v_schema_name || '.XX_EBS_SOD_RESPONSIBILITIES.IRM_JOB_ID = :P11_SYNC_NAME)) AS VALUE, 
                -- Total Value 
                (SELECT COUNT(' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE.ID) 
                FROM ' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE  
                INNER JOIN ' || v_schema_name || '.XX_EBS_SOD_MST  
                    ON ' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE.CONTROL_ID = ' || v_schema_name || '.XX_EBS_SOD_MST.ID  
                LEFT JOIN split_values  
                    ON ' || v_schema_name || '.XX_EBS_SOD_MST.BUSINESS_PROCESS = split_values.BUSINESS_PROCESS  
                LEFT JOIN split_values_1  
                    ON ' || v_schema_name || '.XX_EBS_SOD_MST.RISK_RATING = split_values_1.RISK_RATING  
                WHERE (:1 IS NULL OR :1 = '''' OR split_values.BUSINESS_PROCESS IS NOT NULL)  
                AND (:2 IS NULL OR :2 = '''' OR split_values_1.RISK_RATING IS NOT NULL) 
                AND (:P11_SYNC_NAME IS NULL OR :P11_SYNC_NAME = '''' OR ' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE.IRM_JOB_ID = :P11_SYNC_NAME) 
                AND ('|| v_schema_name ||'.XX_EBS_SOD_MST.CONTROL_TYPE = :P11_CONTROL_TYPE  OR :P11_CONTROL_TYPE IS NULL) 
                AND ('|| v_schema_name ||'.TRN_CONTROL_SECURITY_PROFILE.IS_FALSE_POSITIVE = :P11_CONSIDER_SECURITY_PROFILE  OR :P11_CONSIDER_SECURITY_PROFILE IS NULL) 
                AND ('|| v_schema_name ||'.TRN_CONTROL_SECURITY_PROFILE.ENT_LEG1_INCLUDE_ORGANIZATION_NAME = :P11_LEG1_OU_NAME   
                OR :P11_LEG1_OU_NAME IS NULL) 
                AND ('|| v_schema_name ||'.TRN_CONTROL_SECURITY_PROFILE.ENT_LEG2_INCLUDE_ORGANIZATION_NAME = :P11_LEG2_OU_NAME   
                OR :P11_LEG2_OU_NAME IS NULL)) AS TOTALVAL, 
                -- Sensitive Value 
                (SELECT COUNT(' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE.ENT_LEG1_RESP_NAME) FROM ' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE INNER JOIN ' || v_schema_name || '.XX_EBS_SOD_MST ON ' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE.CONTROL_ID = ' || v_schema_name || '.XX_EBS_SOD_MST.ID LEFT JOIN split_values ON ' || v_schema_name || '.XX_EBS_SOD_MST.BUSINESS_PROCESS = split_values.BUSINESS_PROCESS LEFT JOIN split_values_1 ON ' || v_schema_name || '.XX_EBS_SOD_MST.RISK_RATING = split_values_1.RISK_RATING WHERE ' || v_schema_name || '.XX_EBS_SOD_MST.RISK_RATING LIKE ''%Sensitive%'' AND (:1 IS NULL OR :1 = '''' OR split_values.BUSINESS_PROCESS IS NOT NULL) AND (:2 IS NULL OR :2 = '''' OR split_values_1.RISK_RATING IS NOT NULL) 
                AND (:P11_SYNC_NAME IS NULL OR :P11_SYNC_NAME = '''' OR ' || v_schema_name || '.TRN_CONTROL_SECURITY_PROFILE.IRM_JOB_ID = :P11_SYNC_NAME) 
                AND ('|| v_schema_name ||'.XX_EBS_SOD_MST.CONTROL_TYPE = :P11_CONTROL_TYPE  OR :P11_CONTROL_TYPE IS NULL) 
                AND ('|| v_schema_name ||'.TRN_CONTROL_SECURITY_PROFILE.IS_FALSE_POSITIVE = :P11_CONSIDER_SECURITY_PROFILE  OR :P11_CONSIDER_SECURITY_PROFILE IS NULL) 
                AND ('|| v_schema_name ||'.TRN_CONTROL_SECURITY_PROFILE.ENT_LEG1_INCLUDE_ORGANIZATION_NAME = :P11_LEG1_OU_NAME   
                OR :P11_LEG1_OU_NAME IS NULL) 
                AND ('|| v_schema_name ||'.TRN_CONTROL_SECURITY_PROFILE.ENT_LEG2_INCLUDE_ORGANIZATION_NAME = :P11_LEG2_OU_NAME   
                OR :P11_LEG2_OU_NAME IS NULL)) AS SENSITIVE 
            FROM DUAL 
        ) 
        SELECT  
            NAMES, 
            ACCESST, 
            CRITV, 
            HIGHV, 
            MEDIUMV, 
            VALUE, 
            TOTALVAL, 
            SENSITIVE  
        FROM base_data'; 
    -- Execute the query and fetch data 
    EXECUTE IMMEDIATE l_query BULK COLLECT  
    INTO base_data 
    USING  p_business_process,p_business_process, 
    p_risk_rating,p_risk_rating, 
    p_business_process,p_business_process, 
    p_risk_rating,p_risk_rating, 
    p_sync_id,p_sync_id,p_sync_id, 
    p_control_type,p_control_type, 
    p_business_process,p_business_process, 
    p_risk_rating,p_risk_rating, 
    p_sync_id,p_sync_id,p_sync_id, 
    p_control_type,p_control_type, 
    p_business_process,p_business_process, 
    p_risk_rating,p_risk_rating, 
    p_sync_id,p_sync_id,p_sync_id, 
    p_control_type,p_control_type, 
    p_sync_id,p_sync_id,p_sync_id, 
    p_business_process,p_business_process, 
    p_risk_rating,p_risk_rating, 
    p_sync_id,p_sync_id,p_sync_id, 
    p_control_type,p_control_type, 
    p_business_process,p_business_process, 
    p_risk_rating,p_risk_rating, 
    p_sync_id,p_sync_id,p_sync_id, 
    p_control_type,p_control_type, 
    p_business_process,p_business_process, 
    p_risk_rating,p_risk_rating, 
    p_sync_id,p_sync_id,p_sync_id, 
    p_control_type,p_control_type, 
    p_security_profile_flag,p_security_profile_flag, 
    p_ou_name_leg1,p_ou_name_leg1, 
    p_ou_name_leg2,p_ou_name_leg2, 
    p_business_process,p_business_process, 
    p_risk_rating,p_risk_rating, 
    p_sync_id,p_sync_id,p_sync_id, 
    p_control_type,p_control_type, 
    p_security_profile_flag,p_security_profile_flag, 
    p_ou_name_leg1,p_ou_name_leg1, 
    p_ou_name_leg2,p_ou_name_leg2, 
    p_business_process,p_business_process, 
    p_risk_rating,p_risk_rating, 
    p_sync_id,p_sync_id,p_sync_id, 
    p_control_type,p_control_type, 
    p_security_profile_flag,p_security_profile_flag, 
    p_ou_name_leg1,p_ou_name_leg1, 
    p_ou_name_leg2,p_ou_name_leg2, 
    p_sync_id,p_sync_id,p_sync_id, 
    p_business_process,p_business_process, 
    p_risk_rating,p_risk_rating, 
    p_sync_id,p_sync_id,p_sync_id, 
    p_control_type,p_control_type, 
    p_security_profile_flag,p_security_profile_flag, 
    p_ou_name_leg1,p_ou_name_leg1, 
    p_ou_name_leg2,p_ou_name_leg2, 
    p_business_process,p_business_process, 
    p_risk_rating,p_risk_rating, 
    p_sync_id,p_sync_id,p_sync_id, 
    p_control_type,p_control_type, 
    p_security_profile_flag,p_security_profile_flag, 
    p_ou_name_leg1,p_ou_name_leg1, 
    p_ou_name_leg2,p_ou_name_leg2, 
    p_business_process,p_business_process, 
    p_risk_rating,p_risk_rating, 
    p_sync_id,p_sync_id,p_sync_id, 
    p_control_type,p_control_type, 
    p_security_profile_flag,p_security_profile_flag, 
    p_ou_name_leg1,p_ou_name_leg1, 
    p_ou_name_leg2,p_ou_name_leg2, 
    p_business_process,p_business_process, 
    p_risk_rating,p_risk_rating, 
    p_sync_id,p_sync_id,p_sync_id, 
    p_control_type,p_control_type, 
    p_security_profile_flag,p_security_profile_flag, 
    p_ou_name_leg1,p_ou_name_leg1, 
    p_ou_name_leg2,p_ou_name_leg2, 
    p_business_process,p_business_process, 
    p_risk_rating,p_risk_rating, 
    p_sync_id,p_sync_id,p_sync_id, 
    p_control_type,p_control_type, 
    p_security_profile_flag,p_security_profile_flag, 
    p_ou_name_leg1,p_ou_name_leg1, 
    p_ou_name_leg2,p_ou_name_leg2, 
    p_sync_id,p_sync_id,p_sync_id, 
    p_security_profile_flag,p_security_profile_flag, 
    p_ou_name_leg1,p_ou_name_leg1, 
    p_ou_name_leg2,p_ou_name_leg2, 
    p_business_process,p_business_process, 
    p_risk_rating,p_risk_rating, 
    p_sync_id,p_sync_id,p_sync_id, 
    p_control_type,p_control_type, 
    p_security_profile_flag,p_security_profile_flag, 
    p_ou_name_leg1,p_ou_name_leg1, 
    p_ou_name_leg2,p_ou_name_leg2, 
    p_business_process,p_business_process, 
    p_risk_rating,p_risk_rating, 
    p_sync_id,p_sync_id,p_sync_id, 
    p_control_type,p_control_type, 
    p_security_profile_flag,p_security_profile_flag, 
    p_ou_name_leg1,p_ou_name_leg1, 
    p_ou_name_leg2,p_ou_name_leg2, 
    p_business_process,p_business_process, 
    p_risk_rating,p_risk_rating, 
    p_sync_id,p_sync_id,p_sync_id, 
    p_control_type,p_control_type, 
    p_security_profile_flag,p_security_profile_flag, 
    p_ou_name_leg1,p_ou_name_leg1, 
    p_ou_name_leg2,p_ou_name_leg2, 
    p_business_process,p_business_process, 
    p_risk_rating,p_risk_rating, 
    p_sync_id,p_sync_id,p_sync_id, 
    p_control_type,p_control_type, 
    p_security_profile_flag,p_security_profile_flag, 
    p_ou_name_leg1,p_ou_name_leg1, 
    p_ou_name_leg2,p_ou_name_leg2, 
    p_business_process,p_business_process, 
    p_risk_rating,p_risk_rating, 
    p_sync_id,p_sync_id,p_sync_id, 
    p_control_type,p_control_type, 
    p_security_profile_flag,p_security_profile_flag, 
    p_ou_name_leg1,p_ou_name_leg1, 
    p_ou_name_leg2,p_ou_name_leg2, 
    p_sync_id,p_sync_id,p_sync_id, 
    p_business_process,p_business_process, 
    p_risk_rating,p_risk_rating, 
    p_sync_id,p_sync_id,p_sync_id, 
    p_control_type,p_control_type, 
    p_security_profile_flag,p_security_profile_flag, 
    p_ou_name_leg1,p_ou_name_leg1, 
    p_ou_name_leg2,p_ou_name_leg2, 
    p_business_process,p_business_process, 
    p_risk_rating,p_risk_rating, 
    p_sync_id,p_sync_id,p_sync_id, 
    p_control_type,p_control_type, 
    p_security_profile_flag,p_security_profile_flag, 
    p_ou_name_leg1,p_ou_name_leg1, 
    p_ou_name_leg2,p_ou_name_leg2; 
    FOR i IN 1 .. base_data.COUNT LOOP 
        l_html := l_html || ' 
            <tr> 
                <td class="table-user-data" style="font-size: 1.3rem; padding: 15px; border: 1px solid #ddd; border-radius: 5px; background-color: #f9f9f9; text-align:center;">' || base_data(i).NAMES || '<br>
                    <a href="javascript:void(0);" onclick="openModal(''Value'', ''' || base_data(i).NAMES || ''', ''' || base_data(i).VALUE || ''')" style="font-size: 1.3rem; display:block; margin-top:5px;">' || base_data(i).VALUE || '</a>
                </td> 
                <td class="table-blank-data"></td> 
                <td class="table-access-aspects" style="font-size: 1.3rem; padding: 15px; border: 1px solid #ddd; border-radius: 5px; background-color: #f9f9f9; text-align:left;">' || base_data(i).ACCESST || '</td> 
                <td class="table-access-critical" style="font-size: 1.3rem; padding: 15px; border: 1px solid #ddd; border-radius: 5px; background-color: #f9f9f9; text-align:center;"> 
                    <a href="javascript:void(0);"  
                       onclick="openModal(''Critical'', ''' || base_data(i).NAMES || ''', ' || base_data(i).CRITV || ')"  
                       class="critical-' ||  
                       CASE  
                           WHEN base_data(i).NAMES = 'Active' THEN 'active' 
                           WHEN base_data(i).NAMES = 'Employees' THEN 'employees' 
                           WHEN base_data(i).NAMES = 'Partners' THEN 'partners' 
                           WHEN base_data(i).NAMES = 'Assigned Roles' THEN 'ar' 
                       END || '">' || base_data(i).CRITV || '</a> 
                </td> 
                <td class="table-access-high" style="font-size: 1.3rem; padding: 15px; border: 1px solid #ddd; border-radius: 5px; background-color: #f9f9f9; text-align:center;">
                    <a href="javascript:void(0);" onclick="openModal(''High'', ''' || base_data(i).NAMES || ''', ' || base_data(i).HIGHV || ')">' || base_data(i).HIGHV || '</a>
                </td>  
                <td class="table-access-medium" style="font-size: 1.3rem; padding: 15px; border: 1px solid #ddd; border-radius: 5px; background-color: #f9f9f9; text-align:center;">
                    <a href="javascript:void(0);" onclick="openModal(''Medium'', ''' || base_data(i).NAMES || ''', ' || base_data(i).MEDIUMV || ')">' || base_data(i).MEDIUMV || '</a>
                </td> 
                <td class="table-access-total" style="font-size: 1.3rem; padding: 15px; border: 1px solid #ddd; border-radius: 5px; background-color: #f9f9f9; text-align:center;">
                    <a href="javascript:void(0);" onclick="openModal(''Total'', ''' || base_data(i).NAMES || ''', ' || base_data(i).TOTALVAL || ')">' || base_data(i).TOTALVAL || '</a>
                </td> 
                <td class="table-blank-data"></td> 
                <td class="table-access-sensitive" style="font-size: 1.3rem; padding: 15px; border: 1px solid #ddd; border-radius: 5px; background-color: #f9f9f9; text-align:center;">
                    <a href="javascript:void(0);" onclick="openModal(''Sensitive'', ''' || base_data(i).NAMES || ''', ' || base_data(i).SENSITIVE || ')">' || base_data(i).SENSITIVE || '</a>
                </td> 
            </tr>';             
    END LOOP; 
    l_html := l_html || '</table></div>'; 
    RETURN l_html; 
END FN_EXECUTIVE_ANALYSIS_DASHBOARD_EBS;
/
create or replace FUNCTION FN_GENERATE_JWT_TOKEN_V1
(
    p_profile_id number
)
return varchar2
as

    v_header         VARCHAR2(1000);
    v_payload        VARCHAR2(1000);
    v_sign           VARCHAR2(4000);
    v_token          VARCHAR2(4000);

    v_issued_at      NUMBER;
    v_exp_at         NUMBER;

    v_base64_text    VARCHAR2(4000);
    l_cert_raw       RAW(4000);
    l_sha1_raw       RAW(20);
    l_b64            VARCHAR2(4000);
    l_x5t            VARCHAR2(4000);

    v_public_key_clob  CLOB;
    v_private_key_clob CLOB;

    -- temp vars to read blob
    v_dest_offset    INTEGER := 1;
    v_src_offset     INTEGER := 1;
    v_lang_ctx       INTEGER := DBMS_LOB.DEFAULT_LANG_CTX;
    v_warning        INTEGER;

    v_issuer         VARCHAR2(1000);
    v_sub            VARCHAR2(1000);
    v_aud            VARCHAR2(1000);
    v_exp            number;
    v_pub_blob       BLOB;
    v_priv_blob      BLOB;

BEGIN

    BEGIN
        -- 1. Read BLOBs into CLOB
        SELECT 
            ISS,
            SUB,
            AUD,
            EXP_TIME_MINS,
            PUBLIC_KEY,
            PRIVATE_KEY
        INTO 
            v_issuer,
            v_sub,
            v_aud,
            v_exp,
            v_pub_blob,
            v_priv_blob
        FROM MST_CLIENT_ERP_CONFIG 
        WHERE ID = p_profile_id;

    EXCEPTION WHEN OTHERS THEN

        RETURN NULL;

    END;

  -- Initialize temporary CLOBs
    DBMS_LOB.CREATETEMPORARY(v_public_key_clob, TRUE);
    DBMS_LOB.CREATETEMPORARY(v_private_key_clob, TRUE);

    -- Convert BLOBs to CLOBs
    DBMS_LOB.CONVERTTOCLOB(
        DEST_LOB     => v_public_key_clob,
        SRC_BLOB     => v_pub_blob,
        AMOUNT       => DBMS_LOB.LOBMAXSIZE,
        DEST_OFFSET  => v_dest_offset,
        SRC_OFFSET   => v_src_offset,
        BLOB_CSID    => DBMS_LOB.DEFAULT_CSID,
        LANG_CONTEXT => v_lang_ctx,
        WARNING      => v_warning
    );

    -- Reset offsets before next conversion
    v_dest_offset := 1;
    v_src_offset := 1;

    DBMS_LOB.CONVERTTOCLOB(
        DEST_LOB     => v_private_key_clob,
        SRC_BLOB     => v_priv_blob,
        AMOUNT       => DBMS_LOB.LOBMAXSIZE,
        DEST_OFFSET  => v_dest_offset,
        SRC_OFFSET   => v_src_offset,
        BLOB_CSID    => DBMS_LOB.DEFAULT_CSID,
        LANG_CONTEXT => v_lang_ctx,
        WARNING      => v_warning
    );

    -- 2. Extract and clean the Base64 content from the cert
    v_base64_text := REPLACE(REPLACE(REPLACE(v_public_key_clob, '-----BEGIN CERTIFICATE-----', ''), '-----END CERTIFICATE-----', ''), CHR(10), '');
    v_base64_text := REPLACE(v_base64_text, CHR(13), '');

    -- 3. Convert to RAW
    l_cert_raw := UTL_ENCODE.BASE64_DECODE(UTL_RAW.CAST_TO_RAW(v_base64_text));

    -- 4. Compute SHA-1 for x5t
    l_sha1_raw := IRM_GLOBAL_APP_CONFIG.as_crypto.HASH(l_cert_raw, 3); -- 3 = SHA1

    -- 5. Convert to base64url
    l_b64 := UTL_RAW.CAST_TO_VARCHAR2(UTL_ENCODE.BASE64_ENCODE(l_sha1_raw));
    l_x5t := REPLACE(REPLACE(REPLACE(l_b64, '+', '-'), '/', '_'), '=', '');

    -- 6. Compute iat & exp
    v_issued_at := ROUND((CAST(SYSTIMESTAMP AT TIME ZONE 'UTC' AS DATE) - DATE '1970-01-01') * 86400);
    v_exp_at := round(v_issued_at + (v_exp * 60));

    -- 7. Build header and payload
    v_header := IRM_GLOBAL_APP_CONFIG.as_crypto.base64URL_encode(p_txt => '{"alg":"RS256","typ":"JWT","x5t":"' || l_x5t || '"}');

    v_payload := IRM_GLOBAL_APP_CONFIG.as_crypto.base64URL_encode(p_txt => '{"iss":"'|| v_issuer ||'","sub":"'|| v_sub ||'","aud":"'|| v_aud ||'","iat":' || v_issued_at || ',"exp":' || v_exp_at || '}');

    -- 8. Sign the header.payload
    v_sign := IRM_GLOBAL_APP_CONFIG.as_crypto.base64URL_encode(
        p_raw => IRM_GLOBAL_APP_CONFIG.as_crypto.sign(
            utl_raw.cast_to_raw(v_header || '.' || v_payload),
            utl_raw.cast_to_raw(v_private_key_clob),
            IRM_GLOBAL_APP_CONFIG.as_crypto.KEY_TYPE_RSA,
            IRM_GLOBAL_APP_CONFIG.as_crypto.SIGN_SHA256_RSA
        )
    );

    -- 9. Assemble JWT
    v_token := v_header || '.' || v_payload || '.' || v_sign;

    -- DBMS_OUTPUT.PUT_LINE('JWT Token: ' || v_token);

    return v_token;

EXCEPTION WHEN OTHERS THEN

    return NULL;

END;
/
create or replace function "FN_GEN_RISK_DESC_GROQ_GPT"( 
    p_prompt varchar2 
) 
return clob 
as 
    -- p_prompt nvarchar2(10000) := 'Enhancements & Testing'; 
    l_data CLOB; 
    l_url VARCHAR2(2000) := 'https://api.groq.com/openai/v1/chat/completions'; 
    l_groq_prompt CLOB := '{ 
    "messages": [ 
        { 
          "role": "user", 
          "content": "Give me the risk description for the following Enterprise Risk Management statement - ' || p_prompt || ' within 2 sentences" 
        } 
    ], 
    "model": "mixtral-8x7b-32768" 
    }'; 
    l_gpt_content clob := ''; 
    l_chk_response VARCHAR2(10); 
    l_msg clob; 
BEGIN 
 
    apex_web_service.g_request_headers(1).name := 'Content-type';  
    apex_web_service.g_request_headers(1).value := 'application/json'; 
 
    apex_web_service.g_request_headers(2).name := 'Authorization';  
    apex_web_service.g_request_headers(2).value := 'Bearer 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'; 
 
    /* Make REST API request to FUSION SaaS API */ 
    l_data := apex_web_service.make_rest_request( 
        p_url => l_url, 
        p_http_method => 'POST', 
        p_body => l_groq_prompt 
    ); 
 
    IF apex_web_service.g_status_code >= 400 THEN 
        apex_error.add_error ( 
            p_message          => 'Oops! Error occured. <br /> Reason : ' || apex_web_service.G_REASON_PHRASE, 
            p_display_location => apex_error.c_inline_in_notification  
        ); 
    ELSE 
 
        select  
            tbl.gpt_content into l_gpt_content  
        from 
        json_table( 
            l_data, 
            '$' 
            columns( 
                nested path '$.choices[*]' columns ( 
                    gpt_content clob path '$.message.content' 
                ) 
            ) 
        ) tbl; 
 
        dbms_output.put_line(l_gpt_content); 
 
    END IF; 
 
    return l_gpt_content; 
 
END;
/
create or replace function "FN_GET_ALL_ORG_HIER_FR_CLIENT" 
( 
    p_client_id number /* parameter for client id */ 
) 
return CLOB 
as 
begin 
return  
    'SELECT DISTINCT 
        HIER_LEVEL_NO, 
        ORG_HIERARCHY AS D, 
        ORG_HIERARCHY AS R 
    FROM IRM_GLOBAL_APP_CONFIG.MST_CLIENT_ORG_HIER 
    WHERE CLIENT_ID = ' || p_client_id || ' ORDER BY HIER_LEVEL_NO'; 
 
END "FN_GET_ALL_ORG_HIER_FR_CLIENT";
/
create or replace function "FN_GET_CLIENT_ORG_HIER" 
( 
    p_client_id number, /* parameter for client id */ 
    p_org_hier varchar2 /* parameter for Organization Hiererchy level like Entity, Grroup -> Send text as input in proper case (case sensitive)  */ 
) 
return CLOB 
as 
begin 
return  
    'SELECT 
        IRM_GLOBAL_APP_CONFIG.FN_GET_HIER_NAME_BOTTOM_UP_PARENT(ID) AS D, 
        ID AS R 
    FROM IRM_GLOBAL_APP_CONFIG.MST_CLIENT_ORG_HIER 
    WHERE CLIENT_ID = ' || p_client_id 
    || ' AND ORG_HIERARCHY = ''' || p_org_hier || ''''; 
 
END "FN_GET_CLIENT_ORG_HIER";
/
create or replace FUNCTION FN_GET_CONTROL_REG_TITLE( 
    p_client_id IN NUMBER, 
    p_ids IN VARCHAR2 
) 
RETURN CLOB 
IS 
    v_risk_tracker_app_id NUMBER := 120; 
    v_result CLOB; 
    v_schema_name VARCHAR2(1000); 
    v_query VARCHAR2(4000); 
BEGIN 
    /* Get schema name for Risk Tracker Application for the particular Client */ 
    BEGIN 
        SELECT SA_SCHEMA_NAME INTO v_schema_name 
        FROM IRM_GLOBAL_APP_CONFIG.MST_CLIENT_APP_ERP_SCHEMA 
        WHERE APP_ID = v_risk_tracker_app_id 
        AND CLIENT_ID = p_client_id 
        AND IS_ACTIVE = 'Y'; 
 
        v_query :=  
        'SELECT ( 
            SELECT LISTAGG(rn || ''. '' || NAME, '', <br>'') WITHIN GROUP (ORDER BY rn) 
            FROM (SELECT ROW_NUMBER() OVER (ORDER BY NAME ASC) AS rn, NAME 
               FROM '|| v_schema_name ||'.MST_CONTROLS 
               WHERE INSTR('','' || :ids || '','', '','' || ID || '','') > 0 
            ) rrm_sub 
        ) FROM DUAL'; 
 
        DBMS_OUTPUT.PUT_LINE(v_query); 
 
        BEGIN 
            EXECUTE IMMEDIATE v_query INTO v_result USING p_ids ; 
        EXCEPTION WHEN OTHERS 
            THEN v_result := 'Error ' || SQLERRM ; 
        END; 
 
    EXCEPTION  
    WHEN NO_DATA_FOUND 
        THEN v_result := 'No schema Found!'; 
    END; 
 
    RETURN v_result; 
END;
/
create or replace FUNCTION FN_GET_HIER_NAME_BOTTOM_UP_PARENT( 
    p_hier_id NUMBER 
) 
RETURN VARCHAR2 
IS 
    v_full_hierarchy VARCHAR2(4000); 
BEGIN 
    WITH org_hierarchy (ID, HIER_NAME, PARENT_ID, LEVEL_NO) AS ( 
        -- Start from the leaf node 
        SELECT  
            ID, 
            HIER_NAME, 
            PARENT_ID, 
            1 AS LEVEL_NO 
        FROM mst_client_org_hier 
        WHERE  
        ID = p_hier_id 
         
        UNION ALL 
 
        -- Walk up the hierarchy 
        SELECT  
            parent.ID, 
            parent.HIER_NAME, 
            parent.PARENT_ID, 
            child.LEVEL_NO + 1 
        FROM mst_client_org_hier parent 
        JOIN org_hierarchy child ON parent.ID = child.PARENT_ID 
    ), 
    -- Leaf name 
    leaf AS ( 
        SELECT HIER_NAME AS LEAF_NAME FROM org_hierarchy WHERE LEVEL_NO = 1 
    ), 
    -- Ordered parent path (excluding the leaf) 
    path AS ( 
        SELECT HIER_NAME, LEVEL_NO FROM org_hierarchy WHERE LEVEL_NO > 1 
    ) 
 
    -- Final output: build the full hierarchy string 
    SELECT 
        (SELECT LEAF_NAME FROM leaf) || ' (' || 
        (SELECT LISTAGG(HIER_NAME, ' -> ') WITHIN GROUP (ORDER BY LEVEL_NO ASC) FROM path) ||  
        ')' INTO v_full_hierarchy 
    FROM dual; 
 
    RETURN v_full_hierarchy; 
END;
/
create or replace FUNCTION FN_GET_IMPACT_CATG_TITLE( 
    p_client_id IN NUMBER, 
    p_ids IN VARCHAR2 
) 
RETURN CLOB 
IS 
    v_risk_tracker_app_id NUMBER := 120; 
    v_result CLOB; 
    v_schema_name VARCHAR2(1000); 
    v_query VARCHAR2(4000); 
BEGIN 
    /* Get schema name for Risk Tracker Application for the particular Client */ 
    BEGIN 
        SELECT SA_SCHEMA_NAME INTO v_schema_name 
        FROM IRM_GLOBAL_APP_CONFIG.MST_CLIENT_APP_ERP_SCHEMA 
        WHERE APP_ID = v_risk_tracker_app_id 
        AND CLIENT_ID = p_client_id 
        AND IS_ACTIVE = 'Y'; 
 
        v_query := 'SELECT ( 
            SELECT LISTAGG(rn || ''. '' || NAME, '', <Br>'') WITHIN GROUP (ORDER BY rn) 
            FROM (SELECT ROW_NUMBER() OVER (ORDER BY NAME ASC) AS rn, NAME 
               FROM '|| v_schema_name ||'.MST_IMPACT_CATEGORY 
               WHERE INSTR('','' || :ids || '','', '','' || ID || '','') > 0 
            ) rrm_sub 
        ) FROM DUAL'; 
 
        -- DBMS_OUTPUT.PUT_LINE(v_query); 
 
        BEGIN 
            EXECUTE IMMEDIATE v_query INTO v_result USING p_ids ; 
        EXCEPTION WHEN OTHERS 
            THEN v_result := 'Error ' || SQLERRM ; 
        END; 
 
    EXCEPTION  
    WHEN NO_DATA_FOUND 
        THEN v_result := 'No schema Found!'; 
    END; 
 
    RETURN v_result; 
END;
/
create or replace FUNCTION FN_GET_ONLY_REGULATORY_BODY_NAME_SINGLE( 
    p_client_id IN NUMBER,  
    p_ids IN NUMBER 
) RETURN VARCHAR2 
IS 
    v_compliance_tracker_app_id NUMBER := 132; 
    v_result VARCHAR2(3000); 
    v_schema_name VARCHAR2(1000); 
BEGIN 
    BEGIN 
        SELECT SA_SCHEMA_NAME INTO v_schema_name 
        FROM IRM_GLOBAL_APP_CONFIG.MST_CLIENT_APP_ERP_SCHEMA 
        WHERE APP_ID = v_compliance_tracker_app_id 
          AND CLIENT_ID = p_client_id 
          AND IS_ACTIVE = 'Y'; 
 
        BEGIN 
            EXECUTE IMMEDIATE  
                'SELECT NAME FROM ' || v_schema_name || '.MST_REGULATORY_BODY WHERE ID = :1' 
            INTO v_result 
            USING p_ids; 
        EXCEPTION  
            WHEN NO_DATA_FOUND THEN 
                v_result := 'No Data Found!'; 
            WHEN OTHERS THEN 
                v_result := 'Error: ' || SQLERRM; 
        END; 
    EXCEPTION  
        WHEN NO_DATA_FOUND THEN 
            v_result := 'No schema Found!'; 
    END; 
 
    RETURN v_result; 
END;
/
create or replace FUNCTION FN_GET_ONLY_RISK_REG_TITLE_SINGLE( 
    p_client_id IN NUMBER, 
    p_ids IN NUMBER 
) 
RETURN CLOB 
IS 
    v_risk_tracker_app_id NUMBER := 120; 
    v_result CLOB; 
    v_schema_name VARCHAR2(1000); 
    v_query VARCHAR2(4000); 
BEGIN 
    /* Get schema name for Risk Tracker Application for the particular Client */ 
    BEGIN 
        SELECT SA_SCHEMA_NAME INTO v_schema_name 
        FROM IRM_GLOBAL_APP_CONFIG.MST_CLIENT_APP_ERP_SCHEMA 
        WHERE APP_ID = v_risk_tracker_app_id 
        AND CLIENT_ID = p_client_id 
        AND IS_ACTIVE = 'Y'; 
 
        DBMS_OUTPUT.PUT_LINE(v_schema_name); 
 
        -- v_query := 'SELECT TITLE 
        --        FROM '|| v_schema_name ||'.MST_RISK_REGISTERS 
        --        WHERE ID = ' || p_ids; 
 
        BEGIN 
            EXECUTE IMMEDIATE  
            'SELECT TITLE 
               FROM '|| v_schema_name ||'.MST_RISK_REGISTERS 
               WHERE ID = :p_ids'  
            INTO v_result 
            USING p_ids; 
        EXCEPTION  
        WHEN NO_DATA_FOUND 
            THEN v_result := 'No Risk Found!'; 
        WHEN OTHERS 
            THEN v_result := 'Error ' || SQLERRM ; 
        END; 
 
    EXCEPTION  
    WHEN NO_DATA_FOUND 
        THEN v_result := 'No schema Found!'; 
    END; 
 
    RETURN v_result; 
END;
/
create or replace FUNCTION FN_GET_ORG_HIER_NAMES( 
    p_ids IN VARCHAR2 
) 
RETURN CLOB 
IS 
    v_result CLOB; 
    v_query VARCHAR2(4000); 
BEGIN 
    /* Get Org hierarchy names */ 
    BEGIN 
 
        v_query := 'SELECT ( 
            SELECT LISTAGG(rn || ''. '' || HIER_NAME, '', <br>'') WITHIN GROUP (ORDER BY rn) 
            FROM (SELECT ROW_NUMBER() OVER (ORDER BY HIER_NAME ASC) AS rn, HIER_NAME 
               FROM IRM_GLOBAL_APP_CONFIG.MST_CLIENT_ORG_HIER 
               WHERE INSTR('','' || :ids || '','', '','' || ID || '','') > 0 
            ) rrm_sub 
        ) FROM DUAL'; 
 
        -- DBMS_OUTPUT.PUT_LINE(v_query); 
 
        BEGIN 
            EXECUTE IMMEDIATE v_query INTO v_result USING p_ids ; 
        EXCEPTION WHEN OTHERS 
            THEN v_result := 'Error ' || SQLERRM ; 
        END; 
 
    EXCEPTION  
    WHEN NO_DATA_FOUND 
        THEN v_result := 'No Hierarchy Found!'; 
    WHEN OTHERS 
        THEN v_result := 'Error occured! Error : ' || SQLERRM; 
    END; 
 
    RETURN v_result; 
END;
/
create or replace FUNCTION FN_GET_REMAIN_BOOKMARK_LIMIT( 
    p_client_id NUMBER, 
    p_user_id NUMBER, 
    p_app_id NUMBER 
) 
RETURN NUMBER 
IS 
    l_active_bookmark_cnt NUMBER; 
    l_bookmark_max_limt NUMBER; 
BEGIN 
    /* 
        Function created by Racktim Guin 
        for getting the remaining Bookmark limit against an Application for a User 
    */ 
 
    -- get application wise bookmark maximum limit 
    BEGIN 
        SELECT CONFIG_VAL INTO l_bookmark_max_limt FROM MST_APP_COFIG 
        WHERE CONFIG_NAME = 'MAX_BOOKMARK_LIMIT' 
        AND IS_ACTIVE = 'Y' 
        AND APP_NO = p_app_id 
        AND CLIENT_ID = p_client_id; 
    EXCEPTION 
    WHEN NO_DATA_FOUND 
        THEN l_bookmark_max_limt := 5; -- setting 5 as a limit if no data is found 
    WHEN OTHERS 
        THEN l_bookmark_max_limt := 5; -- setting 5 as a limit if no data is found 
    END; 
 
    -- get the count of bookmarks already added for the particular application 
    SELECT COUNT(ID) INTO l_active_bookmark_cnt FROM TRN_APP_USER_BOOKMARKS 
    WHERE CLIENT_ID = p_client_id 
    AND APP_ID = p_app_id 
    AND USER_ID = p_user_id 
    AND IS_ACTIVE = 'Y'; 
 
    RETURN l_bookmark_max_limt - l_active_bookmark_cnt; 
END;
/
create or replace FUNCTION FN_GET_REPLACED_DATA_V1 ( 
    p_clob_content IN CLOB, 
    p_json_data IN CLOB 
) RETURN CLOB AS 
    TYPE key_value_array IS TABLE OF VARCHAR2(4000) INDEX BY VARCHAR2(1000); 
    v_replacements key_value_array; 
    v_result CLOB; 
    v_key VARCHAR2(1000); 
    v_value VARCHAR2(4000); 
    v_pos NUMBER; 
    v_next_pos NUMBER; 
    v_json_str CLOB; 
    v_pair VARCHAR2(4000); 
BEGIN 
    -- Initialize result with input content 
    v_result := p_clob_content; 
    v_json_str := p_json_data; 
 
    -- Remove curly brackets 
    v_json_str := TRIM(BOTH '{}' FROM v_json_str); 
 
    -- Loop through key-value pairs 
    v_pos := 1; 
    LOOP 
        -- Find the next comma 
        v_next_pos := INSTR(v_json_str, ',"', v_pos); 
        IF v_next_pos = 0 THEN 
            v_pair := SUBSTR(v_json_str, v_pos); 
        ELSE 
            v_pair := SUBSTR(v_json_str, v_pos, v_next_pos - v_pos); 
        END IF; 
 
        -- Extract key and value 
        v_key := TRIM(BOTH '"' FROM SUBSTR(v_pair, 1, INSTR(v_pair, '":"') - 1)); 
        v_value := TRIM(BOTH '"' FROM SUBSTR(v_pair, INSTR(v_pair, '":"') + 3)); 
 
        -- Store in associative array 
        v_replacements(v_key) := v_value; 
 
        -- Exit if no more key-value pairs 
        EXIT WHEN v_next_pos = 0; 
        v_pos := v_next_pos + 2; 
    END LOOP; 
 
    -- Replace placeholders in the email content 
    FOR v_idx IN v_replacements.FIRST .. v_replacements.LAST LOOP 
        v_result := REPLACE(v_result, '[' || v_idx || ']', v_replacements(v_idx)); 
    END LOOP; 
 
    RETURN v_result; 
END FN_GET_REPLACED_DATA_V1;
/
create or replace FUNCTION FN_GET_RISK_LEVEL( 
    /* This function basically multiplies likelihood * impact priority  
    and check the range between which it falls */ 
    p_client_id IN NUMBER, 
    p_impact_id IN NUMBER DEFAULT 0, 
    p_likelihood_id IN NUMBER DEFAULT 0 
) 
RETURN CHAR 
IS 
    l_schema_name VARCHAR2(1000); 
    v_impact_priority NUMBER; 
    v_likeihood_priority NUMBER; 
    l_risk_tracker_app_id NUMBER := 120; 
    l_priority CHAR(1); 
BEGIN 
 
    SELECT SA_SCHEMA_NAME INTO l_schema_name 
    FROM IRM_GLOBAL_APP_CONFIG.MST_CLIENT_APP_ERP_SCHEMA 
    WHERE APP_ID = l_risk_tracker_app_id 
    AND CLIENT_ID = p_client_id 
    AND IS_ACTIVE = 'Y'; 
 
    BEGIN 
        EXECUTE IMMEDIATE 
        'SELECT 
            IL.PRIORITY AS "PRIORITY" 
         FROM ' || l_schema_name || '.MST_LIKELIHOOD_LEVEL IL 
         WHERE IL.IS_ACTIVE = ''Y'' 
         AND ID = ' || p_likelihood_id INTO v_likeihood_priority; 
    EXCEPTION  
    WHEN NO_DATA_FOUND 
        THEN v_likeihood_priority := 0; 
    WHEN OTHERS 
        THEN v_likeihood_priority := 0; 
    END; 
 
    BEGIN 
        EXECUTE IMMEDIATE 
        'SELECT 
            IL.PRIORITY AS "PRIORITY" 
         FROM ' || l_schema_name || '.MST_IMPACT_LEVEL IL 
         WHERE IL.IS_ACTIVE = ''Y'' 
         AND ID = ' || p_impact_id INTO v_impact_priority; 
    EXCEPTION  
    WHEN NO_DATA_FOUND 
        THEN v_impact_priority := 0; 
    WHEN OTHERS 
        THEN v_impact_priority := 0; 
    END; 
 
    CASE   
        WHEN (v_impact_priority * v_likeihood_priority) BETWEEN 1 AND 3 THEN  
            l_priority := 'L';  
        WHEN (v_impact_priority * v_likeihood_priority) BETWEEN 4 AND 8 THEN  
            l_priority := 'M';  
        WHEN (v_impact_priority * v_likeihood_priority) BETWEEN 9 AND 12 THEN  
            l_priority := 'G';  
        WHEN (v_impact_priority * v_likeihood_priority) BETWEEN 13 AND 18 THEN  
            l_priority := 'H';  
        WHEN (v_impact_priority * v_likeihood_priority) > 19 THEN  
            l_priority := 'V'; 
        ELSE l_priority := 'R'; 
    END CASE;  
 
    RETURN l_priority; 
END;
/
create or replace FUNCTION FN_GET_RISK_REG_TITLE( 
    p_client_id IN NUMBER, 
    p_ids IN VARCHAR2 
) 
RETURN CLOB 
IS 
    v_risk_tracker_app_id NUMBER := 120; 
    v_result CLOB; 
    v_schema_name VARCHAR2(1000); 
    v_query VARCHAR2(4000); 
BEGIN 
    /* Get schema name for Risk Tracker Application for the particular Client */ 
    BEGIN 
        SELECT SA_SCHEMA_NAME INTO v_schema_name 
        FROM IRM_GLOBAL_APP_CONFIG.MST_CLIENT_APP_ERP_SCHEMA 
        WHERE APP_ID = v_risk_tracker_app_id 
        AND CLIENT_ID = p_client_id 
        AND IS_ACTIVE = 'Y'; 
 
        v_query := 'SELECT ( 
            SELECT LISTAGG(rn || ''. '' || TITLE, '', <Br>'') WITHIN GROUP (ORDER BY rn) 
            FROM (SELECT ROW_NUMBER() OVER (ORDER BY TITLE ASC) AS rn, TITLE 
               FROM '|| v_schema_name ||'.MST_RISK_REGISTERS 
               WHERE INSTR('','' || :ids || '','', '','' || ID || '','') > 0 
            ) rrm_sub 
        ) FROM DUAL'; 
 
        -- DBMS_OUTPUT.PUT_LINE(v_query); 
 
        BEGIN 
            EXECUTE IMMEDIATE v_query INTO v_result USING p_ids ; 
        EXCEPTION WHEN OTHERS 
            THEN v_result := 'Error ' || SQLERRM ; 
        END; 
 
    EXCEPTION  
    WHEN NO_DATA_FOUND 
        THEN v_result := 'No schema Found!'; 
    END; 
 
    RETURN v_result; 
END;
/
create or replace FUNCTION FN_GET_USER_NAME_GET_EMAIL_V2( 
    /* 
        p_ids => Takes User ID either Single or , separated 
        p_type => (NAME / EMAIL) this parameter takes which column you want for Name give parameter as Name if you want Email you Can give Email as a parameter there is no Case limit. 
    */ 
    p_ids IN VARCHAR2, 
    p_type IN VARCHAR2 DEFAULT 'BOTH' 
) RETURN VARCHAR2 
IS 
    v_result VARCHAR2(4000); 
BEGIN 
    IF UPPER(p_type) = 'NAME' THEN 
        SELECT LISTAGG(TRIM(FIRST_NAME) || ' ' || TRIM(LAST_NAME), ', ') WITHIN GROUP (ORDER BY ID) 
        INTO v_result 
        FROM MST_USERS 
        WHERE ID IN ( 
            SELECT TRIM(REGEXP_SUBSTR(p_ids, '[^,]+', 1, LEVEL)) 
            FROM DUAL 
            CONNECT BY REGEXP_SUBSTR(p_ids, '[^,]+', 1, LEVEL) IS NOT NULL 
        ); 
     
    ELSIF UPPER(p_type) = 'EMAIL' THEN 
        SELECT LISTAGG(TRIM(EMAIL), ', ') WITHIN GROUP (ORDER BY ID) 
        INTO v_result 
        FROM MST_USERS 
        WHERE ID IN ( 
            SELECT TRIM(REGEXP_SUBSTR(p_ids, '[^,]+', 1, LEVEL)) 
            FROM DUAL 
            CONNECT BY REGEXP_SUBSTR(p_ids, '[^,]+', 1, LEVEL) IS NOT NULL 
        ); 
     
    ELSE 
        SELECT LISTAGG(TRIM(FIRST_NAME) || ' ' || TRIM(LAST_NAME)|| ' (' || TRIM(EMAIL) || ')', ', ') WITHIN GROUP (ORDER BY ID) 
        INTO v_result 
        FROM MST_USERS 
        WHERE ID IN ( 
            SELECT TRIM(REGEXP_SUBSTR(p_ids, '[^,]+', 1, LEVEL)) 
            FROM DUAL 
            CONNECT BY REGEXP_SUBSTR(p_ids, '[^,]+', 1, LEVEL) IS NOT NULL 
        ); 
    END IF; 
 
    IF v_result IS NULL THEN 
        RETURN 'No users found for the given IDs'; 
    END IF; 
 
    RETURN v_result; 
 
EXCEPTION 
    WHEN OTHERS THEN 
        RETURN 'Error fetching user details'; 
END FN_GET_USER_NAME_GET_EMAIL_V2;
/
create or replace function FN_HAS_PERMISSION( 
  p_user in varchar2, 
  p_internal_name in varchar2 
) 
return boolean 
as 
  l_has_permission boolean := FALSE; 
  l_count number; 
  l_all_permission_cnt number; 
  v_user_id number; 
  l_all_permission_secondary_cnt number; 
 
  v_user_exist number; 
BEGIN 
 
    SELECT COUNT(1) INTO v_user_exist FROM IRM_GLOBAL_APP_CONFIG.MST_USERS WHERE LOWER(EMAIL) = LOWER(p_user); 
 
    IF v_user_exist > 0 THEN  
 
        BEGIN 
            SELECT  
                COUNT(1) INTO l_count 
            FROM IRM_GLOBAL_APP_CONFIG.TRN_USER_MULTI_ROLE_MAP TPGM 
            JOIN IRM_GLOBAL_APP_CONFIG.MST_USERS EMU ON EMU.ID = TPGM.USER_ID 
            JOIN IRM_GLOBAL_APP_CONFIG.MST_ROLE_COMP_PERM MRCP ON MRCP.ROLE_ID = TPGM.ROLE_ID 
            LEFT JOIN IRM_GLOBAL_APP_CONFIG.TRN_PERM_GRP_WITH_GRP_MAP TPGW ON TPGW.PNT_GRP_ID = MRCP.PERM_GRP_ID OR TPGW.CLD_GRP_ID = MRCP.PERM_GRP_ID AND TPGW.IS_ACTIVE = 'Y' 
            JOIN IRM_GLOBAL_APP_CONFIG.TRN_PERM_GROUP_AND_PERMISSION_MAP TPGAP ON TPGAP.PERM_GRP_ID = MRCP.PERM_GRP_ID OR TPGAP.PERM_GRP_ID = TPGW.PNT_GRP_ID OR TPGAP.PERM_GRP_ID = TPGW.CLD_GRP_ID 
            JOIN IRM_GLOBAL_APP_CONFIG.MST_COMPONENT_PERMISSIONS MCP ON MCP.ID = TPGAP.PERM_ID 
 
            WHERE TPGM.IS_ACTIVE = 'Y'  
              
            AND TPGAP.IS_ACTIVE = 'Y'  
            AND MRCP.IS_ACTIVE = 'Y'  
            AND EMU.IS_ACTIVE = 'Y'  
            AND MCP.IS_ACTIVE = 'Y' 
            AND LOWER(EMU.EMAIL) = LOWER(p_user)  
            AND UPPER(MCP.INTERNAL_NAME) = UPPER(p_internal_name); 
 
            SELECT COUNT(1) INTO l_all_permission_cnt 
            FROM IRM_GLOBAL_APP_CONFIG.TRN_USER_MULTI_ROLE_MAP 
            WHERE ROLE_ID = 0 AND IS_ACTIVE = 'Y' AND USER_ID = (SELECT ID FROM IRM_GLOBAL_APP_CONFIG.MST_USERS WHERE LOWER(EMAIL) = LOWER(p_user)); 
 
        EXCEPTION WHEN OTHERS THEN 
            l_count := 0; 
        END; 
    ELSE 
        l_count := 0; 
    END IF; 
 
    IF l_count > 0 OR l_all_permission_cnt > 0 THEN 
 
        l_has_permission := TRUE; 
    ELSE 
 
        l_has_permission := FALSE; 
    END IF; 
 
    RETURN l_has_permission; 
 
EXCEPTION WHEN OTHERS THEN 
    RETURN FALSE; 
end FN_HAS_PERMISSION;
/
create or replace function FN_HAS_PERMISSION_V2( 
  p_user in varchar2, 
  p_internal_name in varchar2 
) 
return boolean 
as 
  l_has_permission boolean := FALSE; 
  l_count number; 
  l_all_permission_cnt number; 
  v_user_id number; 
  l_all_permission_secondary_cnt number; 
 
  v_user_exist number; 
BEGIN 
 
    SELECT COUNT(1) INTO v_user_exist FROM IRM_GLOBAL_APP_CONFIG.MST_USERS WHERE LOWER(EMAIL) = LOWER(p_user); 
 
    IF v_user_exist > 0 THEN  
 
        BEGIN 
            SELECT  
                COUNT(1) INTO l_count 
            FROM IRM_GLOBAL_APP_CONFIG.TRN_USER_MULTI_ROLE_MAP TPGM 
            JOIN IRM_GLOBAL_APP_CONFIG.MST_USERS EMU ON EMU.ID = TPGM.USER_ID 
            JOIN IRM_GLOBAL_APP_CONFIG.MST_ROLE_COMP_PERM MRCP ON MRCP.ROLE_ID = TPGM.ROLE_ID 
            LEFT JOIN IRM_GLOBAL_APP_CONFIG.TRN_PERM_GRP_WITH_GRP_MAP TPGW ON TPGW.PNT_GRP_ID = MRCP.PERM_GRP_ID OR TPGW.CLD_GRP_ID = MRCP.PERM_GRP_ID AND TPGW.IS_ACTIVE = 'Y' 
            JOIN IRM_GLOBAL_APP_CONFIG.TRN_PERM_GROUP_AND_PERMISSION_MAP TPGAP ON TPGAP.PERM_GRP_ID = MRCP.PERM_GRP_ID OR TPGAP.PERM_GRP_ID = TPGW.PNT_GRP_ID OR TPGAP.PERM_GRP_ID = TPGW.CLD_GRP_ID 
            JOIN IRM_GLOBAL_APP_CONFIG.MST_COMPONENT_PERMISSIONS MCP ON MCP.ID = TPGAP.PERM_ID 
 
            WHERE TPGM.IS_ACTIVE = 'Y'  
              
            AND TPGAP.IS_ACTIVE = 'Y'  
            AND MRCP.IS_ACTIVE = 'Y'  
            AND EMU.IS_ACTIVE = 'Y'  
            AND MCP.IS_ACTIVE = 'Y' 
            AND LOWER(EMU.EMAIL) = LOWER(p_user)  
            AND UPPER(MCP.INTERNAL_NAME) = UPPER(p_internal_name); 
 
            SELECT COUNT(1) INTO l_all_permission_cnt 
            FROM IRM_GLOBAL_APP_CONFIG.TRN_USER_MULTI_ROLE_MAP 
            WHERE ROLE_ID = 0 AND IS_ACTIVE = 'Y' AND USER_ID = (SELECT ID FROM IRM_GLOBAL_APP_CONFIG.MST_USERS WHERE LOWER(EMAIL) = LOWER(p_user)); 
 
        EXCEPTION WHEN OTHERS THEN 
            l_count := 0; 
        END; 
    ELSE 
        l_count := 0; 
    END IF; 
 
    IF l_count > 0 OR l_all_permission_cnt > 0 THEN 
 
        l_has_permission := TRUE; 
    ELSE 
 
        l_has_permission := FALSE; 
    END IF; 
 
    RETURN l_has_permission; 
 
EXCEPTION WHEN OTHERS THEN 
    RETURN FALSE; 
end FN_HAS_PERMISSION_V2;
/
create or replace FUNCTION FN_JWT_TOKEN_GENERATION ( 
    p_username   IN VARCHAR2, 
    p_session_id IN NUMBER 
) RETURN CLOB  
AS  
    v_count         NUMBER; 
    v_jwt_token    CLOB; 
    v_session_status VARCHAR2(1000); 
    v_user_id       NUMBER; 
BEGIN 
    -- Get User ID 
    BEGIN 
        SELECT MAX(id)  
        INTO v_user_id  
        FROM mst_users  
        WHERE is_active = 'Y' AND LOWER(email) = LOWER(p_username); 
    EXCEPTION  
        WHEN NO_DATA_FOUND THEN 
            RETURN 'No data found'; 
        WHEN OTHERS THEN 
            RETURN 'ERROR: ' || SQLERRM; 
    END; 
 
    -- Check if JWT already exists for the session 
    SELECT COUNT(1)  
    INTO v_count  
    FROM JWT_TOKEN_AUTH  
    WHERE SESSION_ID = p_session_id AND TRIM(IS_EXPIRED) = 'N'; 
 
    IF v_count > 0 THEN 
        BEGIN 
            SELECT JWT_TOKEN  
            INTO v_jwt_token  
            FROM JWT_TOKEN_AUTH  
            WHERE SESSION_ID = p_session_id; 
        EXCEPTION  
            WHEN NO_DATA_FOUND THEN 
                RETURN 'JWT token not found for this session.'; 
        END; 
         
        RETURN v_jwt_token; 
    ELSE 
        -- Check session status 
        v_session_status := APEX_UTIL.GET_SESSION_STATE(p_session_id); 
 
        IF v_session_status IS NOT NULL THEN 
            BEGIN 
                
 
 
                v_jwt_token := apex_jwt.encode (  
                            p_iss => 'Example Issuer', 
                            p_sub => 'Example User', 
                            p_aud => 'Example JWT Recipient', 
                            p_exp_sec => 60*5, 
                            p_other_claims => '"session": '||apex_json.stringify(p_session_id)||  
                                            ',"username": '||apex_json.stringify(p_username) ||  
                                            ',"user_id": '||apex_json.stringify(v_user_id), 
                            p_signature_key => 'SDCDSCSD' 
                            );  
            EXCEPTION  
                WHEN OTHERS THEN 
                    RETURN 'ERROR: JWT generation failed - ' || SQLERRM; 
            END; 
        END IF; 
    END IF; 
 
    -- Insert JWT Token into table 
    IF v_jwt_token IS NOT NULL THEN 
        INSERT INTO JWT_TOKEN_AUTH (USER_ID, USER_NAME, SESSION_ID, JWT_TOKEN)  
        VALUES (v_user_id, p_username, p_session_id, v_jwt_token); 
    ELSE 
        RETURN 'Invalid JWT Token'; 
    END IF; 
 
    RETURN v_jwt_token; 
 
EXCEPTION  
    WHEN OTHERS THEN  
        RETURN 'ERROR: ' || SQLERRM; 
END FN_JWT_TOKEN_GENERATION;
/
create or replace FUNCTION FN_REMOVE_BOOKMARK( 
    p_client_id NUMBER, 
    p_user_id NUMBER, 
    p_app_id NUMBER, 
    p_page_id NUMBER 
) 
RETURN VARCHAR2 
IS 
    l_msg VARCHAR2(1000); 
    l_check_if_bookmark_exists NUMBER; 
BEGIN 
    /* 
        Function created by Racktim Guin 
        for removing page from the bookmark list 
    */ 
 
    -- check if Bookmark for this page already exists but in inactive state 
    SELECT COUNT(ID) INTO l_check_if_bookmark_exists FROM TRN_APP_USER_BOOKMARKS 
    WHERE CLIENT_ID = p_client_id 
    AND APP_ID = p_app_id 
    AND USER_ID = p_user_id 
    AND PAGE_ID = p_page_id 
    AND IS_ACTIVE = 'Y'; 
 
    IF l_check_if_bookmark_exists > 0 
        THEN 
        -- Update Bookmark list set IS_ACTIVE = 'N' 
        UPDATE TRN_APP_USER_BOOKMARKS SET IS_ACTIVE = 'N' 
        WHERE CLIENT_ID = p_client_id 
            AND APP_ID = p_app_id 
            AND USER_ID = p_user_id 
            AND PAGE_ID = p_page_id 
            AND IS_ACTIVE = 'Y'; 
        l_msg := 'Successfully removed from Bookmark!'; 
    ELSE 
        l_msg := 'Page does not exist in the Bookmark List!!'; 
    END IF; 
 
    RETURN l_msg; 
END;
/
create or replace function FN_SEND_MAIL_V1( 
    p_client_id NUMBER DEFAULT 0, --Client ID of the Sender 
    p_to VARCHAR2,--Recievevers mails or user ID seperated By ',' , ':' or '~' 
    p_cc VARCHAR2 DEFAULT NULL,--Sender mails or user ID seperated By ',' , ':' or '~' 
    p_subject VARCHAR2,--Subject of the mail 
    p_body CLOB,--The mail body of the mail 
    p_mail_type VARCHAR2 DEFAULT 'SINGLE'--The mail type 'BULK' or null : In Case of Sending all the mails to all users in a single mail and 'SINGLE' : in case of sending mail all the users individually 
     
) 
return varchar2 
as 
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
 
    return v_response; 
end "FN_SEND_MAIL_V1";
/
create or replace function "FN_SEND_NOTIFICATION_V1" 
( 
    p_client_id number DEFAULT NULL, --CLIENT ID OF THE USERS 
    p_app_id number DEFAULT 131, --CURRENT APPLICATION ID 
    p_tgt_pg_id number DEFAULT 1, --THE CONTEXT TARGET PAGE NO 
    p_tgt_pg_item varchar2 DEFAULT NULL,--THE TARGET PAGE'S PAGE ITEM 
    p_src_id varchar2 DEFAULT NULL,--THE CONTEXT ID -- changed by Racktim Guin, as we can pass multiple values in comma separated format, previously was NUMBER
    p_users varchar2,--THE NOTIFICATION RECIEVERS USERS ID OR EMAIL SEPERATED BY '~', ':' OR ',' 
    p_message varchar2--THE MESSEGE YOU WANT TO SHOW IN THE NOTIFIACTION 
) 
return varchar2 
as 
 
    v_users varchar2(4000) := replace(replace(p_users, ':', ','),'~', ','); 
    v_target_url varchar2(1000); 
    v_user_mail varchar2(1000); 
    v_user_id number; 
 
begin 
 
    
    IF p_tgt_pg_item IS NOT NULL THEN 
 
        v_target_url := 'f?p=' || p_app_id || ':' || p_tgt_pg_id || ':#SESSION#::::' || p_tgt_pg_item || ':' || p_src_id; 
 
    ELSE  
 
        v_target_url := 'f?p=' || p_app_id || ':' || p_tgt_pg_id || ':#SESSION#::::'; 
 
    END IF; 
 
 
 
    begin 
 
        for i in ( 
            select column_value as user_id from table(apex_string.split(v_users, ',')) 
        ) loop 
 
            begin 
 
                v_user_id := TO_NUMBER(i.user_id); 
                 
                BEGIN 
 
                    SELECT UPPER(EMAIL) INTO v_user_mail FROM IRM_GLOBAL_APP_CONFIG.MST_USERS 
                    WHERE ID = v_user_id; 
 
                exception when OTHERS then 
 
                    v_user_mail := NULL; 
 
                END; 
 
            exception when VALUE_ERROR then 
 
                v_user_mail := UPPER(i.user_id); 
 
            end; 
 
            IF v_user_mail IS NOT NULL THEN 
 
                insert into IRM_GLOBAL_APP_CONFIG.LOG_NOTIFICATION ( 
                    CLIENT_ID, 
                    USERNAME, 
                    MESSEGE, 
                    TARGET_LINK, 
                    APP_ID 
                ) VALUES ( 
                    p_client_id, 
                    v_user_mail, 
                    p_message, 
                    v_target_url, 
                    p_app_id 
                ); 
 
            END IF; 
 
        end loop; 
    end; 
 
    return 'Notification sent Successfully'; 
 
exception 
  when others then 
 
    IRM_GLOBAL_APP_CONFIG.SP_ERROR_LOGGER_V1( 
        p_client_id => APEX_UTIL.GET_SESSION_STATE('CLIENT_ID'), 
        p_username => SYS_CONTEXT('APEX$SESSION','APP_USER'), 
        p_err_src => 'ERROR FROM FN_SEND_NOTIFICATION_V1', 
        p_err_msg => SQLERRM 
    ); 
    return 'Error during sending notification : ' || SQLERRM; 
 
end "FN_SEND_NOTIFICATION_V1";
/
create or replace FUNCTION FN_SEND_PUSH_NOTIFICATION_V1 ( 
    p_application_id NUMBER, 
    p_user_id        VARCHAR2, 
    p_page_no        NUMBER, 
    p_message        VARCHAR2, 
    p_title          VARCHAR2 
) RETURN VARCHAR2 IS 
    v_link_url VARCHAR2(4000); 
    v_email_list apex_t_varchar2; 
    v_email VARCHAR2(1000); 
    v_result VARCHAR2(4000) := ''; 
BEGIN 
 
    v_link_url := 'f?p=' || p_application_id || ':' || p_page_no || '::APP_SESSION'; 
 
 
    v_email_list := apex_string.split(p_user_id, ','); 
 
 
    FOR i IN 1 .. v_email_list.count LOOP 
        BEGIN 
          
            SELECT email INTO v_email  
            FROM MST_USERS  
            WHERE ID = v_email_list(i); 
 
        
            apex_pwa.send_push_notification( 
                p_application_id => p_application_id, 
                p_user_name      => upper(v_email), 
                p_title          => p_title, 
                p_body           => p_message, 
                p_target_url     => v_link_url 
            ); 
 
            v_result := v_result || 'Notification sent to ' || v_email || '; '; 
        EXCEPTION 
            WHEN OTHERS THEN 
       
                SP_ERROR_LOGGER_V1( 
                    p_username => SYS_CONTEXT('APEX$SESSION', 'APP_USER'), 
                    p_err_src  => 'FN_SEND_PUSH_NOTIFICATION_V1', 
                    p_err_msg  => 'Error sending to ' || v_email || ': ' || SQLERRM 
                ); 
 
                v_result := v_result || 'Failed to send to ' || v_email || '; '; 
        END; 
    END LOOP; 
 
 
    BEGIN 
        apex_pwa.push_queue; 
    EXCEPTION 
        WHEN OTHERS THEN 
            SP_ERROR_LOGGER_V1( 
                p_username => SYS_CONTEXT('APEX$SESSION', 'APP_USER'), 
                p_err_src  => 'FN_SEND_PUSH_NOTIFICATION_V1', 
                p_err_msg  => 'Error in push_queue: ' || SQLERRM 
            ); 
            RETURN 'Error in push_queue: ' || SQLERRM; 
    END; 
 
  
    RETURN v_result; 
 
EXCEPTION 
    WHEN OTHERS THEN 
        SP_ERROR_LOGGER_V1( 
            p_username => SYS_CONTEXT('APEX$SESSION', 'APP_USER'), 
            p_err_src  => 'FN_SEND_PUSH_NOTIFICATION_V1', 
            p_err_msg  => SQLERRM 
        ); 
 
        RETURN 'Error sending notification: ' || SQLERRM; 
END FN_SEND_PUSH_NOTIFICATION_V1;
/
create or replace FUNCTION FN_SHAREPOINT_FILE_UPLOAD_V1 ( -- created_by -> subhankar.das@techriskpartners.com.  created_at -> 07/07/2025
  P_FILE_UPLOAD         IN  VARCHAR2 DEFAULT NULL, -- Enter name of the file to be uploaded [EX - :P65_FILE_UPLOAD]
  P_APP_USER            IN  VARCHAR2, -- Enter APEX user [EX - :APP_USER]
  P_RECIPIENT_USER_ID   IN  VARCHAR2 DEFAULT NULL, -- Enter Colon-separated(:) list of recipient user IDs to share the file or if 'NULL' then non ERP user get access of this file  [EX - '45:85:96']
  P_TYPE                IN  VARCHAR2 DEFAULT 'CREATE',  -- Enter 'CREATE' for fresh upload file, 'UPDATE' to sharing invitation/access for an existing file to new users , 'DELETE' for revoke/remove file access [EX - 'UPDATE']
  P_PERMISSION          IN  VARCHAR2 DEFAULT 'WRITE', -- Enter 'WRITE' for write permission and 'READ' for read permission on this uploaded file

  v_site_id             IN  VARCHAR2 DEFAULT NULL, -- When P_TYPE = 'UPDATE', pass existing SharePoint Site ID of the file  in a table 
  v_item_id             IN  VARCHAR2 DEFAULT NULL, -- When P_TYPE = 'UPDATE', pass existing SharePoint Item ID  in a table (uploaded file ID)
  v_drive_id            IN  VARCHAR2 DEFAULT NULL  -- When P_TYPE = 'UPDATE', pass existing SharePoint Drive ID in a table 
)

-- [NOTE:   1st - Enable upload page item 'Allow Multiple File'
--          2nd - File Upload Table add 'SITE_ID, ITEM_ID ,DRIVE_ID, WEB_URL , FILE_NAME' colums as varchar2
--          3rd - To upload multiple files to SharePoint or to grant access to multiple files for new users, run this function inside a loop]

RETURN SHAREPOINT_FILE_UPLOAD_RESULT -- [DRIVE_ID , SITE_ID , ITEM_ID , WEB_URL , FILE_NAME]
IS
  l_client_id           VARCHAR2(2000);
  l_client_secret       VARCHAR2(2000);
  l_scope               VARCHAR2(1000);

  l_user_ids            APEX_T_VARCHAR2;
  l_file_blob           BLOB;
  l_filename            VARCHAR2(255);
  l_recipient_email     VARCHAR2(2000);

  l_token_response      CLOB;
  l_token_json          apex_json.t_values;
  l_token               VARCHAR2(4000);

  l_drive_response      CLOB;
  l_drive_values        apex_json.t_values;
  l_drive_detail_json   CLOB;
  l_response_values_new apex_json.t_values;
  l_final_url           VARCHAR2(1000);

  l_invite_json         VARCHAR2(4000);
  l_invite_response     CLOB;

  -- Output variables
  P_DRIVE_ID   VARCHAR2(4000);
  P_SITE_ID    VARCHAR2(1000);
  P_ITEM_ID    VARCHAR2(4000);
  P_WEB_URL    VARCHAR2(4000);
  P_FILE_NAME  VARCHAR2(255);
BEGIN

    IF UPPER(P_TYPE) = 'UPDATE' THEN
        
        IRM_GLOBAL_APP_CONFIG.PR_SHAREPOINT_REINVITE_USERS_V1 (
          P_APP_USER         => P_APP_USER,
          P_REINVITE_IDS     => P_RECIPIENT_USER_ID,
          P_PERMISSION       => P_PERMISSION, 
          P_SITE_ID          => v_site_id,
          P_DRIVE_ID         => v_drive_id,
          P_ITEM_ID          => v_item_id
        );

        -- Return existing references
        RETURN SHAREPOINT_FILE_UPLOAD_RESULT(v_drive_id, v_site_id, v_item_id, NULL, NULL);

    ELSIF UPPER(P_TYPE) = 'DELETE' THEN
       
        IRM_GLOBAL_APP_CONFIG.PR_SHAREPOINT_REMOVE_ALL_ACCESS_V1 (
          P_APP_USER         => P_APP_USER,
          P_SITE_ID          => v_site_id,
          P_DRIVE_ID         => v_drive_id,
          P_ITEM_ID          => v_item_id
        );

        -- Return existing references
        RETURN SHAREPOINT_FILE_UPLOAD_RESULT(v_drive_id, v_site_id, v_item_id, NULL, NULL);


    ELSIF UPPER(P_TYPE) = 'CREATE' THEN

      
      SELECT CLIENT_ID, CLIENT_SECRET, SCOPE
        INTO l_client_id, l_client_secret, l_scope
        FROM IRM_GLOBAL_APP_CONFIG.MST_MICROSOFT_ENTRA_CREDENTIALS;

        -- Build invite JSON
        l_invite_json := '[{"email": "' || REPLACE(P_APP_USER, '"', '\"') || '"}';

        -- Build list of user IDs
        IF P_RECIPIENT_USER_ID IS NOT NULL THEN
          l_user_ids := APEX_STRING.SPLIT(P_RECIPIENT_USER_ID, ':');
        ELSE
          SELECT ID
            BULK COLLECT INTO l_user_ids
            FROM IRM_GLOBAL_APP_CONFIG.MST_USERS
           WHERE IS_ACTIVE = 'Y'
             AND IS_ONLY_ERP_USERS = 'N';
        END IF;

        -- Loop through and append user emails
        FOR i IN 1 .. l_user_ids.COUNT LOOP
          BEGIN
            SELECT EMAIL INTO l_recipient_email
              FROM IRM_GLOBAL_APP_CONFIG.MST_USERS
             WHERE ID = l_user_ids(i);

            l_invite_json := l_invite_json || ', {"email": "' || REPLACE(l_recipient_email, '"', '\"') || '"}';
          EXCEPTION
            WHEN NO_DATA_FOUND THEN
              NULL;
          END;
        END LOOP;

        l_invite_json := l_invite_json || ']';



      SELECT ID INTO P_SITE_ID
        FROM IRM_GLOBAL_APP_CONFIG.MST_MICROSOFT_DYNAMIC_USERS_SITES
       WHERE DISPLAYNAME = (
         SELECT DISPLAYNAME
           FROM IRM_GLOBAL_APP_CONFIG.MST_SHAREPOINT_USERS
          WHERE LOWER(MAIL) = LOWER(P_APP_USER)
       );

      apex_web_service.g_request_headers.delete;
      apex_web_service.g_request_headers(1).name := 'Content-Type';
      apex_web_service.g_request_headers(1).value := 'application/x-www-form-urlencoded';

      l_token_response := apex_web_service.make_rest_request(
        p_url => 'https://login.microsoftonline.com/ffd87c9b-d203-42db-a8c1-16909eaafe2d/oauth2/v2.0/token',
        p_http_method => 'POST',
        p_body => 'grant_type=client_credentials' ||
                  '&client_id=' || l_client_id ||
                  '&client_secret=' || l_client_secret ||
                  '&scope=https://graph.microsoft.com/.default'
      );

      apex_json.parse(l_token_json, l_token_response);
      l_token := apex_json.get_varchar2(p_path => 'access_token', p_values => l_token_json);

      apex_web_service.g_request_headers.delete;
      apex_web_service.g_request_headers(1).name := 'Authorization';
      apex_web_service.g_request_headers(1).value := 'Bearer ' || l_token;
      apex_web_service.g_request_headers(2).name := 'Content-Type';
      apex_web_service.g_request_headers(2).value := 'application/json';

      l_drive_response := apex_web_service.make_rest_request(
        p_url => 'https://graph.microsoft.com/v1.0/sites/' || P_SITE_ID || '/drives',
        p_http_method => 'GET'
      );

      apex_json.parse(l_drive_values, l_drive_response);
      P_DRIVE_ID := apex_json.get_varchar2(p_path => 'value[1].id', p_values => l_drive_values);

      l_filename := P_FILE_UPLOAD;
      SELECT blob_content INTO l_file_blob
        FROM apex_application_temp_files
       WHERE name = l_filename;

      l_final_url := 'https://graph.microsoft.com/v1.0/sites/' || P_SITE_ID ||
                     '/drives/' || P_DRIVE_ID || '/root:/DocumentManagementSystem/' ||
                     l_filename || ':/content';

      l_drive_detail_json := apex_web_service.make_rest_request(
        p_url        => l_final_url,
        p_http_method => 'PUT',
        p_body_blob   => l_file_blob
      );

      apex_json.parse(l_response_values_new, l_drive_detail_json);
      P_ITEM_ID   := apex_json.get_varchar2(p_path => 'id',     p_values => l_response_values_new);
      P_WEB_URL   := apex_json.get_varchar2(p_path => 'webUrl', p_values => l_response_values_new);
      P_FILE_NAME := apex_json.get_varchar2(p_path => 'name',   p_values => l_response_values_new);

      apex_web_service.g_request_headers.delete;
      apex_web_service.g_request_headers(1).name := 'Authorization';
      apex_web_service.g_request_headers(1).value := 'Bearer ' || l_token;
      apex_web_service.g_request_headers(2).name := 'Content-Type';
      apex_web_service.g_request_headers(2).value := 'application/json';

      l_invite_response := apex_web_service.make_rest_request(
        p_url         => 'https://graph.microsoft.com/v1.0/sites/' || P_SITE_ID ||
                         '/drives/' || P_DRIVE_ID || '/items/' || P_ITEM_ID || '/invite',
        p_http_method => 'POST',
        p_body        => '{
          "recipients": ' || l_invite_json || ',
          "message": "Here is the file you requested.",
          "requireSignIn": true,
          "sendInvitation": true,
          "roles": ["'|| LOWER(P_PERMISSION) || '"]
        }'
      );

    ELSE
      RAISE_APPLICATION_ERROR(-20002, 'Invalid P_TYPE. Allowed: CREATE, UPDATE, DELETE . So please correct parameter pass');
    END IF ; 
    

    RETURN SHAREPOINT_FILE_UPLOAD_RESULT(
    
      DRIVE_ID   => P_DRIVE_ID,
    
      SITE_ID    => P_SITE_ID,
    
      ITEM_ID    => P_ITEM_ID,
    
      WEB_URL    => P_WEB_URL,
    
      FILE_NAME  => P_FILE_NAME
    
    );


EXCEPTION
  WHEN OTHERS THEN
    RAISE_APPLICATION_ERROR(-20001, 'Error in FN_SHAREPOINT_FILE_UPLOAD_V1: ' || SQLERRM);
END FN_SHAREPOINT_FILE_UPLOAD_V1;
/
create or replace FUNCTION format_number(p_number NUMBER) 
RETURN VARCHAR2 IS
BEGIN
    IF p_number IS NULL THEN
        RETURN NULL;
    END IF;
    
    CASE 
        WHEN ABS(p_number) >= 1000000000 THEN 
            RETURN TRIM(TO_CHAR(ROUND(p_number/1000000000, 1), '999990.9')) || 'B';
        WHEN ABS(p_number) >= 1000000 THEN 
            RETURN TRIM(TO_CHAR(ROUND(p_number/1000000, 1), '999990.9')) || 'M';
        WHEN ABS(p_number) >= 1000 THEN 
            RETURN TRIM(TO_CHAR(ROUND(p_number/1000, 1), '999990.9')) || 'K';
        ELSE 
            RETURN TO_CHAR(p_number);
    END CASE;
END format_number;
/
create or replace function f_hash_password( 
    p_password varchar2 
  ) return varchar2 
  as 
  begin 
    return 
      oos_util_crypto.hash_str( 
        p_src => p_password 
        , p_typ => oos_util_crypto.gc_hash_sh256 
      ) 
    ; 
  end f_hash_password;
/
create or replace FUNCTION generate_org_chart_html(p_client_id IN NUMBER)  
RETURN CLOB  
IS 
    l_html CLOB := ''; 
    l_prev_level NUMBER := 0; 
BEGIN 
    FOR rec IN ( 
        SELECT  
            mcoh.ID AS NODE_ID, 
            mcoh.PARENT_ID, 
            mcoh.CLIENT_ID, 
            '<div class="node ' || CASE  
                WHEN LEVEL = 1 THEN 'red'  
                WHEN LEVEL = 2 THEN 'blue'  
                ELSE 'gray'  
            END || '">'  
            || mc.CLIENT_NAME || ' - ' || mcoh.ORG_HIERARCHY || ': ' || mcoh.HIER_NAME ||  
            '</div>' AS LABEL, 
            LEVEL AS HIERARCHY_LEVEL 
        FROM MST_CLIENT_ORG_HIER mcoh 
        JOIN MST_CLIENT mc ON mcoh.CLIENT_ID = mc.ID 
        WHERE mcoh.IS_ACTIVE = 'Y' AND (mcoh.CLIENT_ID = p_client_id OR p_client_id IS NULL) 
        START WITH mcoh.PARENT_ID IS NULL 
        CONNECT BY PRIOR mcoh.ID = mcoh.PARENT_ID 
        ORDER SIBLINGS BY mcoh.HIER_NAME 
    ) LOOP 
        IF rec.HIERARCHY_LEVEL > l_prev_level THEN 
            l_html := l_html || '<div class="branch"><div class="line"></div><div class="tree">'; 
        ELSIF rec.HIERARCHY_LEVEL < l_prev_level THEN 
            l_html := l_html || '</div></div>'; 
        END IF; 
 
        l_html := l_html || rec.LABEL; 
        l_prev_level := rec.HIERARCHY_LEVEL; 
    END LOOP; 
 
    -- Close any remaining open tags 
    IF l_prev_level > 0 THEN 
        l_html := l_html || '</div></div>'; 
    END IF; 
 
    -- Return the generated HTML 
    RETURN l_html; 
END;
/
create or replace FUNCTION GetMD5(p_string IN VARCHAR2) RETURN VARCHAR2 IS 
    v_hash RAW(16); 
BEGIN 
    v_hash := DBMS_CRYPTO.HASH(UTL_RAW.CAST_TO_RAW(p_string), DBMS_CRYPTO.HASH_MD5); 
    RETURN RAWTOHEX(v_hash);  -- Convert RAW to HEX for readability 
END GetMD5;
/ 