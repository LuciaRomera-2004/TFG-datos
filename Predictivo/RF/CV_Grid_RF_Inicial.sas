PROC IMPORT DATAFILE="D:\UCM\Curso 4\Resultados\Predictivo\Base_Final_Predictivo.xlsx"
    OUT=datos_tfg
    DBMS=XLSX
    REPLACE;
    GETNAMES=YES;
RUN;

* 1. PREPARACIÓN Y CREACIÓN DE FOLDS (CV = 5);
data datos_tfg;
    set datos_tfg;
    if Est_Salud = "Malo" then Salud_bin = 1;
    else if Est_Salud = "Bueno" then Salud_bin = 0;

    /* Asignamos un fold aleatorio del 1 al 5 a cada observación */
    call streaminit(12345);
    fold = mod(_n_, 5) + 1; 
run;

* 2. GRID SEARCH CON VALIDACIÓN CRUZADA;
%let mtry_list   = 3 5 7 9;          
%let ntrees_list = 100 200 300 400;    
%let train_list  = 60 70 80; 

%macro borrar_macro_antigua;
    %if %sysmacexec(grid_cv5) %then %do;
        proc catalog cat=work.sasmacr;
            delete grid_cv5 / et=macro;
        run;
    %end;
%mend borrar_macro_antigua;
%borrar_macro_antigua;

* Tabla limpia para guardar los promedios finales de la CV;
data resultados_cv_final;
    length mtry ntrees trainfraction Mean_Error Mean_Se_Train Mean_Se_Test 8;
    stop;
run;

%macro grid_cv5;
    %local i j k f total_m total_t total_s valor_mtry valor_ntrees valor_train_entero;
    
    %let total_m = %sysfunc(countw(&mtry_list));
    %let total_t = %sysfunc(countw(&ntrees_list));
    %let total_s = %sysfunc(countw(&train_list));

    * Bucle 1: MTRY;
    %do i = 1 %to &total_m;
        %let valor_mtry = %scan(&mtry_list, &i);
        
        * Bucle 2: NTREES;
        %do j = 1 %to &total_t;
            %let valor_ntrees = %scan(&ntrees_list, &j);
            
            * Bucle 3: TRAINFRACTION;
            %do k = 1 %to &total_s;
                %let valor_train_entero = %scan(&train_list, &k);

                * Tabla temporal para acumular los 5 folds;
                data resultados_bucles_folds;
                    length fold mtry ntrees trainfraction Error Se_Train Se_Test 8;
                    stop;
                run;

                * INTERACCIONES DE VALIDACIÓN CRUZADA (1 a 5);
                %do f = 1 %to 5;

                    data datos_cv_temp;
                        set datos_tfg;
                        if fold = &f. then partition_role = 0; * Validar/Test (20%);
                        else partition_role = 1;               * Entrenar (80%);
                    run;

                    * Ejecución calculando el decimal sobre la marcha en SAS;
                    proc hpforest data=datos_cv_temp
                        maxtrees=&valor_ntrees
                        vars_to_try=&valor_mtry
                        trainfraction=%sysevalf(&valor_train_entero / 100)
                        maxdepth=8
                        leafsize=26
                        seed=12345;
                        target Salud_bin / level=binary;
                        input Edad Comp1-Comp7 / level=interval;
                        id partition_role Salud_bin;
                        partition rolevar=partition_role(train='1' validate='0');
                        ods output FitStatistics=fit_tmp;
                        score out=pred_tmp; 
                    run;

                    * Calculamos las sensibilidades;
                    proc sql noprint;
                        select mean(case when Salud_bin = 1 and P_Salud_bin1 > 0.33 then 1 else 0 end)
                        into :v_se_train
                        from pred_tmp
                        where Salud_bin = 1 and partition_role = 1;

                        select mean(case when Salud_bin = 1 and P_Salud_bin1 > 0.33 then 1 else 0 end)
                        into :v_se_test
                        from pred_tmp
                        where Salud_bin = 1 and partition_role = 0;
                    quit;

                    * Extraemos el error global;
                    data fit_tmp2;
                        set fit_tmp end=last;
                        if last;
                        fold = &f.;
                        mtry = &valor_mtry;
                        ntrees = &valor_ntrees;
                        trainfraction = %sysevalf(&valor_train_entero / 100);
                        Error = MiscAll;
                        Se_Train = &v_se_train;
                        Se_Test = &v_se_test;
                        keep fold mtry ntrees trainfraction Error Se_Train Se_Test;
                    run;

                    proc append base=resultados_bucles_folds data=fit_tmp2 force; run;

                %end; 

                * PROMEDIAMOS los resultados de los 5 folds;
                proc summary data=resultados_bucles_folds mean noprint;
                    var Error Se_Train Se_Test;
                    output out=res_promediados(drop=_type_ _freq_) 
                           mean(Error Se_Train Se_Test) = Mean_Error Mean_Se_Train Mean_Se_Test;
                run;

                data res_promediados;
                    set res_promediados;
                    mtry = &valor_mtry;
                    ntrees = &valor_ntrees;
                    trainfraction = %sysevalf(&valor_train_entero / 100);
                run;

                proc append base=resultados_cv_final data=res_promediados force; run;

            %end; 
        %end;     
    %end;         

%mend grid_cv5;

%grid_cv5;

* 3. ORDENACIÓN Y PRESENTACIÓN DE RESULTADOS;
proc sort data=resultados_cv_final;
    by descending Mean_Se_Test;
run;

proc print data=resultados_cv_final;
    title "RESULTADO FINAL: Grid Search 1 con CV=5";
run;
