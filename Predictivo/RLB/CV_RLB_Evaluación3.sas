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
    IF Est_Salud = "Malo"  THEN Salud_bin = 1;
    ELSE IF Est_Salud = "Bueno" THEN Salud_bin = 0;
RUN;


* 2. PARTICIÓN TRAIN / TEST;
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


* PASO 0. ASIGNAR FOLD A CADA OBSERVACIÓN DE TRAIN;
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

* PASO 6. MODELO REDUCIDO UMBRAL YOUDEN DENTRO DE CV k=5;
data resultados_cv_youden;
    length modelo $40;
    length fold AUC Accuracy Sensibilidad Especificidad cutoff_youden 8;
    stop;
run;

%macro cv_logistica_youden(modelo=, vars=);

    %do f = 1 %to 5;

        data cv_train cv_val;
            set train_cv;
            if fold=&f then output cv_val;
            else output cv_train;
        run;

        * Entrenar y obtener curva ROC sobre cv_train;
        proc logistic data=cv_train;
            model Salud_bin(event='1') = &vars
                  / outroc=roc_fold_&f;
            score data=cv_val out=score_val_y_&f;
        run;

        * Calcular Youden en cv_train y extraer cutoff óptimo;
        data roc_fold_&f;
            set roc_fold_&f;
            youden = _sensit_ + (1 - _1mspec_) - 1;
        run;

        proc sql noprint;
            select _PROB_
            into :cutoff_f trimmed
            from roc_fold_&f
            where youden = (select max(youden) from roc_fold_&f)
            order by _PROB_ desc;
        quit;

        * Aplicar cutoff Youden sobre cv_val;
        data score_val_y_&f;
            set score_val_y_&f;
            phat = P_1;
            pred = (phat >= &cutoff_f);
        run;

        * AUC;
        proc sql noprint;
            select mean(case
                        when a.phat > b.phat then 1
                        when a.phat = b.phat then 0.5
                        else 0 end)
            into :auc_f trimmed
            from score_val_y_&f a,
                 score_val_y_&f b
            where a.Salud_bin = 1
              and b.Salud_bin = 0;
        quit;

        * Métricas;
        proc sql noprint;
            select sum(case when Salud_bin=pred then 1 else 0 end)/count(*)
            into :acc_f trimmed
            from score_val_y_&f;

            select sum(case when Salud_bin=1 and pred=1 then 1 else 0 end) /
                   sum(case when Salud_bin=1 then 1 else 0 end)
            into :se_f trimmed
            from score_val_y_&f;

            select sum(case when Salud_bin=0 and pred=0 then 1 else 0 end) /
                   sum(case when Salud_bin=0 then 1 else 0 end)
            into :sp_f trimmed
            from score_val_y_&f;
        quit;

        data fold_res_y;
            length modelo $40;
            modelo          = "&modelo";
            fold            = &f;
            AUC             = &auc_f;
            Accuracy        = &acc_f;
            Sensibilidad    = &se_f;
            Especificidad   = &sp_f;
            cutoff_youden   = &cutoff_f;
        run;

        proc append base=resultados_cv_youden data=fold_res_y force;
        run;

    %end;

%mend cv_logistica_youden;

%cv_logistica_youden(modelo=Reducido_Youden,
                     vars=Comp1 Comp2 Comp5 Comp6 Comp7);


* PASO 7. RESUMEN MODELO REDUCIDO CON YOUDEN;
proc means data=resultados_cv_youden mean std min max;
    class modelo;
    var AUC Accuracy Sensibilidad Especificidad cutoff_youden;
    title "CV k=5 Modelo reducido con umbral Youden por fold";
run;


* PASO 8. REENTRENAR EN TRAIN COMPLETO Y EVALUAR EN TEST
           Cutoff final = media de los cutoffs Youden de los 5 folds;
proc sql noprint;
    select mean(cutoff_youden)
    into :cutoff_final trimmed
    from resultados_cv_youden
    where modelo = "Reducido_Youden";
quit;

%put Cutoff final promedio Youden: &cutoff_final;

proc logistic data=train;
    model Salud_bin(event='1') = Comp1 Comp2 Comp5 Comp6 Comp7;
    score data=test out=pred_test_final;
run;

data pred_test_final;
    set pred_test_final;
    phat = P_1;
    pred = (phat >= &cutoff_final);
run;

proc sql;
    title "Evaluación final en TEST Modelo reducido con umbral Youden";
    select
        sum(case when Salud_bin=pred  then 1 else 0 end)/count(*) as Accuracy,
        sum(case when Salud_bin=1 and pred=1 then 1 else 0 end) /
        sum(case when Salud_bin=1 then 1 else 0 end)              as Sensibilidad,
        sum(case when Salud_bin=0 and pred=0 then 1 else 0 end) /
        sum(case when Salud_bin=0 then 1 else 0 end)              as Especificidad
    from pred_test_final;
quit;
