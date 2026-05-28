* UMBRAL DE DECISI”N;
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

* 2. PARTICI”N TRAIN;
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

* 3. ASIGNAR FOLDS A TRAIN;
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


* 4. TABLA VACÕA RESULTADOS;
   ========================= */
data resultados_umbrales;
    length fold threshold 8;
    length Se Sp Acc Error TP FP TN FN 8;
    stop;
run;


* 5. MACRO M…TRICAS CON UMBRAL;
%macro calc_metrics_cv(thresh=, pred=, fold=, out=);
    data _tmp;
        set score_val;
        &pred = (phat >= &thresh);
    run;

    proc freq data=_tmp noprint;
        tables Salud_bin*&pred / out=_f;
    run;

    data &out;
        set _f end=eof;
        retain TP FN FP TN 0;
        if Salud_bin=1 and &pred=1 then TP=COUNT;
        if Salud_bin=1 and &pred=0 then FN=COUNT;
        if Salud_bin=0 and &pred=1 then FP=COUNT;
        if Salud_bin=0 and &pred=0 then TN=COUNT;
        if eof then do;
            fold      = &fold;
            threshold = &thresh;
            Se        = TP / (TP + FN);
            Sp        = TN / (TN + FP);
            Acc       = (TP + TN) / (TP + TN + FP + FN);
            Error     = 1 - Acc;
            output;
        end;
        keep fold threshold Se Sp Acc Error TP FP TN FN;
    run;
%mend;


* 6. MACRO CON CV Y UMBRAL;
%macro umbrales_cv_arbol;

    %do f = 1 %to 5;

        * ParticiÛn del fold;
        data cv_train cv_val;
            set train_cv;
            if fold = &f then output cv_val;
            else output cv_train;
        run;

        * Entrenar ·rbol en cv_train;
        proc hpsplit data=cv_train seed=12345
            maxdepth=8
            minleafsize=26
            plots=none;
            class Salud_bin;
            model Salud_bin(event='1') =
                Comp1 Comp2 Comp3 Comp4 Comp5 Comp6 Comp7 Edad;
            grow gini;
            prune costcomplexity;
            partition fraction(validate=0.2);
            code file="D:\UCM\arbol_cv_f&f..sas";
        run;

        * Aplicar ·rbol a cv_val;
        data score_val;
            set cv_val;
            %include "D:\UCM\arbol_cv_f&f..sas";
            phat = P_Salud_bin1;
        run;

        * Calcular mÈtricas para cada umbral;
        %calc_metrics_cv(thresh=0.50, pred=pred_050, fold=&f, out=m_050_f&f);
        %calc_metrics_cv(thresh=0.40, pred=pred_040, fold=&f, out=m_040_f&f);
        %calc_metrics_cv(thresh=0.36, pred=pred_036, fold=&f, out=m_036_f&f);
        %calc_metrics_cv(thresh=0.35, pred=pred_035, fold=&f, out=m_035_f&f);
        %calc_metrics_cv(thresh=0.34, pred=pred_034, fold=&f, out=m_034_f&f);
        %calc_metrics_cv(thresh=0.33, pred=pred_033, fold=&f, out=m_033_f&f);
        %calc_metrics_cv(thresh=0.32, pred=pred_032, fold=&f, out=m_032_f&f);
        %calc_metrics_cv(thresh=0.31, pred=pred_031, fold=&f, out=m_031_f&f);
        %calc_metrics_cv(thresh=0.30, pred=pred_030, fold=&f, out=m_030_f&f);
        %calc_metrics_cv(thresh=0.20, pred=pred_020, fold=&f, out=m_020_f&f);
        %calc_metrics_cv(thresh=0.10, pred=pred_010, fold=&f, out=m_010_f&f);

        * Apilar resultados del fold;
        data fold_umbrales;
            set m_050_f&f m_040_f&f m_036_f&f m_035_f&f m_034_f&f
                m_033_f&f m_032_f&f m_031_f&f m_030_f&f m_020_f&f m_010_f&f;
        run;

        proc append base=resultados_umbrales data=fold_umbrales force;
        run;

    %end;

%mend umbrales_cv_arbol;

ods graphics off;
%umbrales_cv_arbol;


* 7. TABLA RESUMEN;
proc sql;
    create table tabla_umbrales_cv as
    select
        threshold,
        mean(Se)    as Se_media,
        mean(Sp)    as Sp_media,
        mean(Acc)   as Acc_media,
        mean(Error) as Error_media,
        mean(TP)    as TP_medio,
        mean(FP)    as FP_medio,
        mean(TN)    as TN_medio,
        mean(FN)    as FN_medio
    from resultados_umbrales
    group by threshold
    order by threshold descending;
quit;

proc print data=tabla_umbrales_cv noobs;
    var threshold Se_media Sp_media Acc_media Error_media
        TP_medio FP_medio TN_medio FN_medio;
    format Se_media Sp_media Acc_media Error_media 6.4
           TP_medio FP_medio TN_medio FN_medio 8.1;
    title "B˙squeda umbral decisiÛn ·Årbol final (maxdepth=8, minleafsize=26) media CV";
run;
