PROC IMPORT DATAFILE="D:\UCM\Curso 4\Resultados\Predictivo\Base_Final_Predictivo.xlsx"
    OUT=datos_tfg
    DBMS=XLSX
    REPLACE;
    GETNAMES=YES;
RUN;

* VARIABLE DEPENDIENTE;
data datos_tfg;

    set datos_tfg;

    if Est_Salud = "Malo" then Salud_bin = 1;
    else if Est_Salud = "Bueno" then Salud_bin = 0;

run;

* PARTICIÓN TRAIN-TEST;
proc surveyselect data=datos_tfg
    out=particion
    samprate=0.8
    seed=12345
    outall;
run;

data train test;

    set particion;

    if Selected = 1 then output train;
    else output test;

run;

* CREAR FOLDS CV = 5;
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


* TABLA FINAL;
data comparacion_final;

    length Modelo_Final $20;
    length fold Sensibilidad 8;

    stop;

run;


* GANADOR REGRESIÓN LOGÍSTICA;
%macro cv_logistica;

    %do f = 1 %to 5;

        data cv_train cv_val;

            set train_cv;

            if fold=&f then output cv_val;
            else output cv_train;

        run;


        proc logistic data=cv_train;

            model Salud_bin(event='1') =
                Comp1 Comp2 Comp5 Comp6 Comp7;

            score data=cv_val out=score_log;

        run;


        data score_log;

            set score_log;

            phat = P_1;

            pred = (phat >= 0.2993);

        run;


        proc sql noprint;

            select
                sum(case when Salud_bin=1 and pred=1 then 1 else 0 end)
                /
                sum(case when Salud_bin=1 then 1 else 0 end)

            into :se_log trimmed

            from score_log;

        quit;


        data log_fold;

            length Modelo_Final $20;

            Modelo_Final = "Logistica";

            fold = &f;

            Sensibilidad = &se_log;

        run;


        proc append
            base=comparacion_final
            data=log_fold
            force;
        run;

    %end;

%mend cv_logistica;

%cv_logistica;


* GANADOR ÁRBOL CLASIFICACIÓN;
%macro cv_arbol;

    %do f = 1 %to 5;

        data cv_train cv_val;

            set train_cv;

            if fold=&f then output cv_val;
            else output cv_train;

        run;


        proc hpsplit data=cv_train
            seed=12345
            maxdepth=8
            minleafsize=26
            plots=none;

            class Salud_bin;

            model Salud_bin(event='1') =
                Comp1 Comp2 Comp3 Comp4
                Comp5 Comp6 Comp7 Edad;

            grow gini;

            prune costcomplexity;

            partition fraction(validate=0.2);

            code file="D:\UCM\tree_final_&f..sas";

        run;


        data score_tree;

            set cv_val;

            %include "D:\UCM\tree_final_&f..sas";

            phat = P_Salud_bin1;

            pred = (phat >= 0.33);

        run;


        proc sql noprint;

            select
                sum(case when Salud_bin=1 and pred=1 then 1 else 0 end)
                /
                sum(case when Salud_bin=1 then 1 else 0 end)

            into :se_tree trimmed

            from score_tree;

        quit;


        data tree_fold;

            length Modelo_Final $20;

            Modelo_Final = "Arbol";

            fold = &f;

            Sensibilidad = &se_tree;

        run;


        proc append
            base=comparacion_final
            data=tree_fold
            force;
        run;

    %end;

%mend cv_arbol;

%cv_arbol;


* GANADOR RANDOM FOREST;
%macro cv_rf;

    %do f = 1 %to 5;

        data datos_cv_temp;

            set train_cv;

            if fold = &f then partition_role = 0;
            else partition_role = 1;

        run;


        proc hpforest data=datos_cv_temp
            maxtrees=250
            vars_to_try=5
            trainfraction=0.45
            maxdepth=8
            leafsize=26
            seed=12345;

            target Salud_bin / level=binary;

            input Edad Comp1-Comp7 / level=interval;

            id partition_role Salud_bin;

            partition rolevar=partition_role(
                train='1'
                validate='0'
            );

            score out=pred_rf;

        run;


        proc sql noprint;

            select
                mean(
                    case
                        when Salud_bin = 1
                             and P_Salud_bin1 > 0.33
                        then 1
                        else 0
                    end
                )

            into :se_rf trimmed

            from pred_rf

            where partition_role = 0
              and Salud_bin = 1;

        quit;


        data rf_fold;

            length Modelo_Final $20;

            Modelo_Final = "RandomForest";

            fold = &f;

            Sensibilidad = &se_rf;

        run;


        proc append
            base=comparacion_final
            data=rf_fold
            force;
        run;

    %end;

%mend cv_rf;

%cv_rf;


* TABLA RESUMEN;
proc means data=comparacion_final
           mean std min max;

    class Modelo_Final;

    var Sensibilidad;

    title "Comparación final de sensibilidad";

run;


* BOXPLOT PARA ELECCION MEJOR MODELO;
proc sgplot data=comparacion_final;

    vbox Sensibilidad /
        category=Modelo_Final
        fillattrs=(transparency=0.3)
        lineattrs=(thickness=1.5)
        meanattrs=(symbol=diamondfilled color=red);

    scatter x=Modelo_Final
            y=Sensibilidad /
            jitter
            transparency=0.25;

    xaxis label="Modelo";

    yaxis label="Sensibilidad"
          min=0.5
          max=1
          values=(0.5 to 1 by 0.05);

    title "Comparación final de sensibilidad mediante validación cruzada";

run;
