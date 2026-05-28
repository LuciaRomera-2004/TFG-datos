* Modelo Completo (CV);
PROC IMPORT DATAFILE="D:\UCM\Curso 4\Resultados\Predictivo\Base_Final_Predictivo.xlsx"
    OUT=datos_tfg
    DBMS=XLSX
    REPLACE;
    GETNAMES=YES;
RUN;

PROC PRINT DATA=datos_tfg (OBS=10);
RUN;


* 1. CREAR VARIABLE DEPENDIENTE;
DATA datos_tfg;
    SET datos_tfg;

    IF Est_Salud = "Malo" THEN Salud_bin = 1;
    ELSE IF Est_Salud = "Bueno" THEN Salud_bin = 0;
RUN;


* 2. PARTICIÓN TRAIN-TEST;
proc surveyselect data=datos_tfg
    out=particion
    samprate=0.8
    seed=12345
    outall;
run;

data train test;
    set particion;

    if Selected=1 then output train;
    else output test;
run;


* PASO 0. ASIGNAR FOLDS;
proc surveyselect data=train
    out=train_cv
    method=srs
    samprate=1
    seed=12345
    outall;
run;

data train_cv;
    set train_cv;
    fold = mod(_n_, 5) + 1;
run;


* PASO 1. TABLA RESULTADOS;
data resultados_cv;
    length modelo $40;
    length fold AUC Accuracy Sensibilidad Especificidad 8;
    stop;
run;


* PASO 2. MACRO VALIDACIÓN CRUZADA;
%macro cv_logistica(modelo=, vars=);

    %do f = 1 %to 5;

        * Separar fold train-validación;
        data cv_train cv_val;
            set train_cv;

            if fold=&f then output cv_val;
            else output cv_train;
        run;


        * Entrenar modelo;
        proc logistic data=cv_train;
            model Salud_bin(event='1') = &vars;
            score data=cv_val out=score_val_&f;
        run;


        * Predicción cutoff 0.5;
        data score_val_&f;
            set score_val_&f;

            phat = P_1;
            pred = (phat >= 0.5);
        run;


        * AUC;
        proc sql noprint;
            select mean(case
                        when a.phat > b.phat then 1
                        when a.phat = b.phat then 0.5
                        else 0 end)
            into :auc_f trimmed
            from score_val_&f a,
                 score_val_&f b
            where a.Salud_bin = 1
              and b.Salud_bin = 0;
        quit;


        * Accuracy;
        proc sql noprint;

            select
                sum(case when Salud_bin=pred then 1 else 0 end)/count(*)
            into :acc_f trimmed
            from score_val_&f;

            select
                sum(case when Salud_bin=1 and pred=1 then 1 else 0 end) /
                sum(case when Salud_bin=1 then 1 else 0 end)
            into :se_f trimmed
            from score_val_&f;

            select
                sum(case when Salud_bin=0 and pred=0 then 1 else 0 end) /
                sum(case when Salud_bin=0 then 1 else 0 end)
            into :sp_f trimmed
            from score_val_&f;

        quit;


        * Guardar métricas;
        data fold_res;

            length modelo $40;

            modelo        = "&modelo";
            fold          = &f;

            AUC           = &auc_f;
            Accuracy      = &acc_f;
            Sensibilidad  = &se_f;
            Especificidad = &sp_f;

        run;


        proc append base=resultados_cv
                    data=fold_res
                    force;
        run;

    %end;

%mend cv_logistica;

* PASO 3. EJECUTAR MODELO;
%let vars = Comp1 Comp2 Comp3 Comp4 Comp5 Comp6 Comp7 Edad;

%cv_logistica(vars=&vars);


* PASO 4. RESUMEN;
proc means data=resultados_cv mean std min max;

    class modelo;

    var AUC
        Accuracy
        Sensibilidad
        Especificidad;

    title "CV k=5 — Modelo completo";

run;


* PASO 5. BOXPLOTS;
* AUC;
proc sgplot data=resultados_cv;

    vbox AUC / category=modelo
               fillattrs=(transparency=0.3)
               lineattrs=(thickness=1.5);

    xaxis label="Modelo";
    yaxis label="AUC" min=0.5 max=1;

    title "CV k=5 — AUC";

run;


* Accuracy;
proc sgplot data=resultados_cv;

    vbox Accuracy / category=modelo
                    fillattrs=(transparency=0.3)
                    lineattrs=(thickness=1.5);

    xaxis label="Modelo";
    yaxis label="Accuracy" min=0.5 max=1;

    title "CV k=5 — Accuracy";

run;


* Sensibilidad;
proc sgplot data=resultados_cv;

    vbox Sensibilidad / category=modelo
                        fillattrs=(transparency=0.3)
                        lineattrs=(thickness=1.5);

    xaxis label="Modelo";
    yaxis label="Sensibilidad" min=0 max=1;

    title "CV k=5 — Sensibilidad";

run;


* Especificidad;
proc sgplot data=resultados_cv;

    vbox Especificidad / category=modelo
                         fillattrs=(transparency=0.3)
                         lineattrs=(thickness=1.5);

    xaxis label="Modelo";
    yaxis label="Especificidad" min=0 max=1;

    title "CV k=5 — Especificidad";

run;


* Modelo sin Comp4 (CV);
PROC IMPORT DATAFILE="D:\UCM\Curso 4\Resultados\Predictivo\Base_Final_Predictivo.xlsx"
    OUT=datos_tfg
    DBMS=XLSX
    REPLACE;
    GETNAMES=YES;
RUN;

PROC PRINT DATA=datos_tfg (OBS=10);
RUN;


* 1. CREAR VARIABLE DEPENDIENTE;
DATA datos_tfg;
    SET datos_tfg;

    IF Est_Salud = "Malo" THEN Salud_bin = 1;
    ELSE IF Est_Salud = "Bueno" THEN Salud_bin = 0;
RUN;


* 2. PARTICIÓN TRAIN-TEST;
proc surveyselect data=datos_tfg
    out=particion
    samprate=0.8
    seed=12345
    outall;
run;

data train test;
    set particion;

    if Selected=1 then output train;
    else output test;
run;


* PASO 0. ASIGNAR FOLDS;
proc surveyselect data=train
    out=train_cv
    method=srs
    samprate=1
    seed=12345
    outall;
run;

data train_cv;
    set train_cv;
    fold = mod(_n_,5) + 1;
run;


* PASO 1. TABLA RESULTADOS;
data resultados_cv;
    length modelo $40;
    length fold AUC Accuracy Sensibilidad Especificidad 8;
    stop;
run;


* PASO 2. MACRO VALIDACIÓN CRUZADA;
%macro cv_logistica(modelo=, vars=);

    %do f = 1 %to 5;

        * Separar fold train-validación;
        data cv_train cv_val;
            set train_cv;

            if fold=&f then output cv_val;
            else output cv_train;
        run;


        * Entrenar modelo;
        proc logistic data=cv_train;
            model Salud_bin(event='1') = &vars;
            score data=cv_val out=score_val_&f;
        run;


        * Predicción cutoff 0.5;
        data score_val_&f;
            set score_val_&f;

            phat = P_1;
            pred = (phat >= 0.5);
        run;


        * AUC;
        proc sql noprint;
            select mean(case
                        when a.phat > b.phat then 1
                        when a.phat = b.phat then 0.5
                        else 0 end)
            into :auc_f trimmed
            from score_val_&f a,
                 score_val_&f b
            where a.Salud_bin = 1
              and b.Salud_bin = 0;
        quit;


        * Accuracy;
        proc sql noprint;

            select
                sum(case when Salud_bin=pred then 1 else 0 end)/count(*)
            into :acc_f trimmed
            from score_val_&f;

            select
                sum(case when Salud_bin=1 and pred=1 then 1 else 0 end) /
                sum(case when Salud_bin=1 then 1 else 0 end)
            into :se_f trimmed
            from score_val_&f;

            select
                sum(case when Salud_bin=0 and pred=0 then 1 else 0 end) /
                sum(case when Salud_bin=0 then 1 else 0 end)
            into :sp_f trimmed
            from score_val_&f;

        quit;


        * Guardar métricas;
        data fold_res;

            length modelo $40;

            modelo        = "&modelo";
            fold          = &f;

            AUC           = &auc_f;
            Accuracy      = &acc_f;
            Sensibilidad  = &se_f;
            Especificidad = &sp_f;

        run;


        proc append base=resultados_cv
                    data=fold_res
                    force;
        run;

    %end;

%mend cv_logistica;

* PASO 3. EJECUTAR MODELO;
%let vars_modelo = Comp1 Comp2 Comp3 Comp5 Comp6 Comp7 Edad;

%cv_logistica(modelo=Sin_Comp4,
              vars=&vars_modelo);


* PASO 4. RESUMEN;
proc means data=resultados_cv mean std min max;

    class modelo;

    var AUC
        Accuracy
        Sensibilidad
        Especificidad;

    title "CV k=5 — Modelo reducido";

run;


* PASO 5. BOXPLOTS;
* AUC;
proc sgplot data=resultados_cv;

    vbox AUC / category=modelo
               fillattrs=(transparency=0.3)
               lineattrs=(thickness=1.5);

    xaxis label="Modelo";
    yaxis label="AUC" min=0.5 max=1;

    title "CV k=5 — AUC";

run;


* Accuracy;
proc sgplot data=resultados_cv;

    vbox Accuracy / category=modelo
                    fillattrs=(transparency=0.3)
                    lineattrs=(thickness=1.5);

    xaxis label="Modelo";
    yaxis label="Accuracy" min=0.5 max=1;

    title "CV k=5 — Accuracy";

run;


* Sensibilidad;
proc sgplot data=resultados_cv;

    vbox Sensibilidad / category=modelo
                        fillattrs=(transparency=0.3)
                        lineattrs=(thickness=1.5);

    xaxis label="Modelo";
    yaxis label="Sensibilidad" min=0 max=1;

    title "CV k=5 — Sensibilidad";

run;


* Especificidad;
proc sgplot data=resultados_cv;

    vbox Especificidad / category=modelo
                         fillattrs=(transparency=0.3)
                         lineattrs=(thickness=1.5);

    xaxis label="Modelo";
    yaxis label="Especificidad" min=0 max=1;

    title "CV k=5 — Especificidad";

run;



* Modelo reducido (CV);
PROC IMPORT DATAFILE="D:\UCM\Curso 4\Resultados\Predictivo\Base_Final_Predictivo.xlsx"
    OUT=datos_tfg
    DBMS=XLSX
    REPLACE;
    GETNAMES=YES;
RUN;

PROC PRINT DATA=datos_tfg (OBS=10);
RUN;


* 1. CREAR VARIABLE DEPENDIENTE;
DATA datos_tfg;
    SET datos_tfg;

    IF Est_Salud = "Malo" THEN Salud_bin = 1;
    ELSE IF Est_Salud = "Bueno" THEN Salud_bin = 0;
RUN;


* 2. PARTICIÓN TRAIN-TEST;
proc surveyselect data=datos_tfg
    out=particion
    samprate=0.8
    seed=12345
    outall;
run;

data train test;
    set particion;

    if Selected=1 then output train;
    else output test;
run;

* PASO 0. ASIGNAR FOLDS;
proc surveyselect data=train
    out=train_cv
    method=srs
    samprate=1
    seed=12345
    outall;
run;

data train_cv;
    set train_cv;
    fold = mod(_n_,5) + 1;
run;


* PASO 1. TABLA RESULTADOS;
data resultados_cv;
    length modelo $40;
    length fold AUC Accuracy Sensibilidad Especificidad 8;
    stop;
run;


* PASO 2. MACRO VALIDACIÓN CRUZADA;
%macro cv_logistica(modelo=, vars=);

    %do f = 1 %to 5;

        * Separar fold train-validación;
        data cv_train cv_val;
            set train_cv;

            if fold=&f then output cv_val;
            else output cv_train;
        run;


        * Entrenar modelo;
        proc logistic data=cv_train;
            model Salud_bin(event='1') = &vars;
            score data=cv_val out=score_val_&f;
        run;


        * Predicción cutoff 0.5;
        data score_val_&f;
            set score_val_&f;

            phat = P_1;
            pred = (phat >= 0.5);
        run;


        * AUC;
        proc sql noprint;
            select mean(case
                        when a.phat > b.phat then 1
                        when a.phat = b.phat then 0.5
                        else 0 end)
            into :auc_f trimmed
            from score_val_&f a,
                 score_val_&f b
            where a.Salud_bin = 1
              and b.Salud_bin = 0;
        quit;


        * Accuracy;
        proc sql noprint;

            select
                sum(case when Salud_bin=pred then 1 else 0 end)/count(*)
            into :acc_f trimmed
            from score_val_&f;

            select
                sum(case when Salud_bin=1 and pred=1 then 1 else 0 end) /
                sum(case when Salud_bin=1 then 1 else 0 end)
            into :se_f trimmed
            from score_val_&f;

            select
                sum(case when Salud_bin=0 and pred=0 then 1 else 0 end) /
                sum(case when Salud_bin=0 then 1 else 0 end)
            into :sp_f trimmed
            from score_val_&f;

        quit;


        * Guardar métricas;
        data fold_res;

            length modelo $40;

            modelo        = "&modelo";
            fold          = &f;

            AUC           = &auc_f;
            Accuracy      = &acc_f;
            Sensibilidad  = &se_f;
            Especificidad = &sp_f;

        run;


        proc append base=resultados_cv
                    data=fold_res
                    force;
        run;

    %end;

%mend cv_logistica;


* PASO 3. EJECUTAR MODELO REDUCIDO;
%let vars_reducido = Comp1 Comp2 Comp5 Comp6 Comp7;

%cv_logistica(modelo=Reducido,
              vars=&vars_reducido);


* PASO 4. RESUMEN;
proc means data=resultados_cv mean std min max;

    class modelo;

    var AUC
        Accuracy
        Sensibilidad
        Especificidad;

    title "CV k=5 — Modelo reducido";

run;


* PASO 5. BOXPLOTS;
* AUC;
proc sgplot data=resultados_cv;

    vbox AUC / category=modelo
               fillattrs=(transparency=0.3)
               lineattrs=(thickness=1.5);

    xaxis label="Modelo";
    yaxis label="AUC" min=0.5 max=1;

    title "CV k=5 — AUC";

run;


* Accuracy;
proc sgplot data=resultados_cv;

    vbox Accuracy / category=modelo
                    fillattrs=(transparency=0.3)
                    lineattrs=(thickness=1.5);

    xaxis label="Modelo";
    yaxis label="Accuracy" min=0.5 max=1;

    title "CV k=5 — Accuracy";

run;


* Sensibilidad;
proc sgplot data=resultados_cv;

    vbox Sensibilidad / category=modelo
                        fillattrs=(transparency=0.3)
                        lineattrs=(thickness=1.5);

    xaxis label="Modelo";
    yaxis label="Sensibilidad" min=0 max=1;

    title "CV k=5 — Sensibilidad";

run;


* Especificidad;
proc sgplot data=resultados_cv;

    vbox Especificidad / category=modelo
                         fillattrs=(transparency=0.3)
                         lineattrs=(thickness=1.5);

    xaxis label="Modelo";
    yaxis label="Especificidad" min=0 max=1;

    title "CV k=5 — Especificidad";

run;
