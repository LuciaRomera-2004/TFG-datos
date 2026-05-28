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

* 2. PARTICIÓN TRAIN;
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

* VALIDACIÓN CRUZADA MACRO;

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


* PASO 1. TABLA VACÍA PARA GUARDAR RESULTADOS;
data resultados_cv_arbol;
    length maxdepth minleafsize fold AUC Accuracy Sensibilidad Especificidad 8;
    stop;
run;


* PASO 2. MACRO DE UN FOLD;
%macro cv_hpsplit_fold(d=, l=, f=);

    * Partición del fold;
    data cv_train cv_val;
        set train_cv;
        if fold = &f then output cv_val;
        else output cv_train;
    run;

    * Entrenar árbol y exportar código;
    proc hpsplit data=cv_train seed=12345
        maxdepth=&d
        minleafsize=&l
        plots=none;
        class Salud_bin;
        model Salud_bin(event='1') =
            Comp1 Comp2 Comp3 Comp4 Comp5 Comp6 Comp7 Edad;
        grow gini;
        prune costcomplexity;
        partition fraction(validate=0.2);
        code file="D:\UCM\cv_tree_&d._&l._f&f..sas";
    run;

    * Aplicar árbol al fold de validación;
    data score_val;
        set cv_val;
        %include "D:\UCM\cv_tree_&d._&l._f&f..sas";
        phat = P_Salud_bin1;
        pred = (phat >= 0.5);
    run;

    * AUC (Wilcoxon);
    proc sql noprint;
        select mean(case
                    when a.phat > b.phat then 1
                    when a.phat = b.phat then 0.5
                    else 0 end)
        into :auc_f trimmed
        from score_val a, score_val b
        where a.Salud_bin = 1 and b.Salud_bin = 0;
    quit;

   * Métricas de clasificación;
    proc sql noprint;
        select sum(case when Salud_bin=pred then 1 else 0 end) / count(*)
        into :acc_f trimmed
        from score_val;

        select sum(case when Salud_bin=1 and pred=1 then 1 else 0 end) /
               sum(case when Salud_bin=1 then 1 else 0 end)
        into :se_f trimmed
        from score_val;

        select sum(case when Salud_bin=0 and pred=0 then 1 else 0 end) /
               sum(case when Salud_bin=0 then 1 else 0 end)
        into :sp_f trimmed
        from score_val;
    quit;

    * Guardar resultados del fold;
    data fold_res;
        maxdepth      = &d;
        minleafsize   = &l;
        fold          = &f;
        AUC           = &auc_f;
        Accuracy      = &acc_f;
        Sensibilidad  = &se_f;
        Especificidad = &sp_f;
    run;

    proc append base=resultados_cv_arbol data=fold_res force;
    run;

%mend cv_hpsplit_fold;


* PASO 3. MACRO GRID llama al macro de fold para cada
           combinación de hiperparámetros;
%macro grid_cv_arbol;

    %let depths = 5 7 9 10 12;
    %let leaves = 5 10 20 50;
    %let n_d = %sysfunc(countw(&depths));
    %let n_l = %sysfunc(countw(&leaves));

    %do i = 1 %to &n_d;
        %let d = %scan(&depths, &i);
        %do j = 1 %to &n_l;
            %let l = %scan(&leaves, &j);
            %do f = 1 %to 5;
                %cv_hpsplit_fold(d=&d, l=&l, f=&f);
            %end;
        %end;
    %end;

%mend grid_cv_arbol;

ods graphics off;
%grid_cv_arbol;


* PASO 4. TABLA RESUMEN (media y desv.típica por arquitectura);
proc means data=resultados_cv_arbol mean std min max;
    class maxdepth minleafsize;
    var AUC Accuracy Sensibilidad Especificidad;
    title "Resumen CV k=5 Árbol de Clasificación (Grid Inicial)";
run;


* PASO 5. RANKING POR AUC MEDIO;
proc sql;
    create table ranking_arbol as
    select maxdepth, minleafsize,
           mean(AUC)           as AUC_medio,
           std(AUC)            as AUC_std,
           mean(Accuracy)      as Acc_medio,
           mean(Sensibilidad)  as Se_medio,
           mean(Especificidad) as Sp_medio
    from resultados_cv_arbol
    group by maxdepth, minleafsize
    order by calculated AUC_medio descending;
quit;

proc print data=ranking_arbol noobs;
    format AUC_medio AUC_std Acc_medio Se_medio Sp_medio 6.4;
    title "Ranking arquitecturas CV k=5 (ordenado por AUC medio)";
run;
