classdef min_max_problem < prost.problem
    properties
        num_primal_vars
        num_dual_vars
        
        primal_vars 
        dual_vars
    end
    
    methods
        function obj = min_max_problem(primals, duals)
            obj = obj@prost.problem();
            
            obj.num_primal_vars = prod(size(primals));
            obj.num_dual_vars = prod(size(duals));

            obj.primal_vars = primals;
            obj.dual_vars = duals;
           
            % initialize indices of primal variables and set prox_g to zero
            primal_idx = 0;
            for i=1:obj.num_primal_vars
                obj.primal_vars{i}.idx = primal_idx;
                
                num_sub_vars = prod(size(primals{i}.sub_vars));
                sub_var_idx = 0;
                for j=1:num_sub_vars
                    obj.primal_vars{i}.sub_vars{j}.idx = primal_idx + sub_var_idx;
                    
                    sub_var_idx = sub_var_idx + primals{i}.sub_vars{j}.dim;
                end
                
                if (sub_var_idx ~= primals{i}.dim) && (num_sub_vars ...
                                                       > 0)
                    error(['Size of subvariables does not match size ' ...
                           'of parent variable.']);
                end
                
                primal_idx = primal_idx + primals{i}.dim;
            end
        
            % initialize indices of dual variables and set
            % prox_fstar to zero
            dual_idx = 0;
            for i=1:obj.num_dual_vars
                obj.dual_vars{i}.idx = dual_idx;
                
                num_sub_vars = prod(size(duals{i}.sub_vars));
                sub_var_idx = 0;
                for j=1:num_sub_vars
                    obj.dual_vars{i}.sub_vars{j}.idx = dual_idx + sub_var_idx;
                    
                    sub_var_idx = sub_var_idx + duals{i}.sub_vars{j}.dim;
                end
                
                if (sub_var_idx ~= duals{i}.dim) && (num_sub_vars ...
                                                     > 0)
                    error(['Size of subvariables does not match size ' ...
                           'of parent variable.']);
                end

                dual_idx = dual_idx + duals{i}.dim;
            end
            
            obj.nrows = dual_idx;
            obj.ncols = primal_idx;            
        end
        
        function obj = add_function(obj, var, func)
            for i=1:obj.num_primal_vars
                num_sub_vars = prod(size(obj.primal_vars{i}.sub_vars));
                for j=1:num_sub_vars
                    if obj.primal_vars{i}.sub_vars{j} == var
                        obj.data.prox_g = add_prox(...
                            func(obj.primal_vars{i}.sub_vars{j}.idx, ...
                                 obj.primal_vars{i}.sub_vars{j}.dim), ...
                            obj.data.prox_g);
                        return;
                    end
                end
                
                if obj.primal_vars{i} == var
                    obj.data.prox_g = add_prox(...
                        func(obj.primal_vars{i}.idx, ...
                             obj.primal_vars{i}.dim), ...
                        obj.data.prox_g);
                    return;
                end
            end
            
            for i=1:obj.num_dual_vars
                num_sub_vars = prod(size(obj.dual_vars{i}.sub_vars));
                for j=1:num_sub_vars
                    if obj.dual_vars{i}.sub_vars{j} == var
                        obj.data.prox_fstar = add_prox(...
                            func(obj.dual_vars{i}.sub_vars{j}.idx, ...
                                 obj.dual_vars{i}.sub_vars{j}.dim), ...
                            obj.data.prox_fstar);
                        return;
                    end
                end
                
                if obj.dual_vars{i} == var
                    obj.data.prox_fstar = add_prox(...
                        func(obj.dual_vars{i}.idx, obj.dual_vars{i}.dim), ...
                        obj.data.prox_fstar);
                    return;
                end
            end
            
            error('Variable not registered in problem!');
        end
        
        function obj = add_dual_pair(obj, pv, dv, block)
            row = -1;
            col = -1;
            dual_dim = -1;
            primal_dim = -1;
                       
            % find primal variable and set column
            for i=1:obj.num_primal_vars
                num_sub_vars = prod(size(obj.primal_vars{i}.sub_vars));
                for j=1:num_sub_vars
                    if obj.primal_vars{i}.sub_vars{j} == pv
                        col = obj.primal_vars{i}.sub_vars{j}.idx;
                        primal_dim = obj.primal_vars{i}.sub_vars{j}.dim;
                    end
                end
                
                if obj.primal_vars{i} == pv
                    col = obj.primal_vars{i}.idx;
                    primal_dim = obj.primal_vars{i}.dim;
                end
            end

            % find dual variable and set row
            for i=1:obj.num_dual_vars
                num_sub_vars = prod(size(obj.dual_vars{i}.sub_vars));
                for j=1:num_sub_vars
                    if obj.dual_vars{i}.sub_vars{j} == dv
                        row = obj.dual_vars{i}.sub_vars{j}.idx;
                        dual_dim = obj.dual_vars{i}.sub_vars{j}.dim;
                    end
                end
                
                if obj.dual_vars{i} == dv
                    row = obj.dual_vars{i}.idx;
                    dual_dim = obj.dual_vars{i}.dim;
                end
            end
            
            if (row == -1) || (col == -1)
                error('Variable pair not registered in problem.');
            end
            
            nrows = dual_dim;
            ncols = primal_dim;
            
            block_size_pair = block(row, col, nrows, ncols);
            
            %obj.data.linop{end + 1} = block_size_pair{1};
            
            % Check if a constraint between pv and dv already exists
            num_blocks = prod(size(obj.data.linop));
            linop_idx = -1;
            for i=1:num_blocks
                linop = obj.data.linop{i};
                
                if (linop{2} == row) && (linop{3} == col)
                    linop_idx = i;
                    break;
                end
            end
            
            if linop_idx == -1 % No constraint present -> add
                               % constraint
                obj.data.linop{end + 1} = block_size_pair{1};
            else % constraint is replaced.
                obj.data.linop{linop_idx} = block_size_pair{1};
            end
            
            sz = block_size_pair{2};
            if (sz{1} ~= dual_dim) || (sz{2} ~= primal_dim)
                error(['Size of block does not fit size of primal/dual ' ...
                       'variable.']);
            end
        end
        
        function obj = fill_variables(obj, result)
            for i=1:obj.num_primal_vars
                idx = obj.primal_vars{i}.idx;
                obj.primal_vars{i}.val = result.x(idx+1:idx+ ...
                                                  obj.primal_vars{i}.dim);
                
                num_sub_vars = prod(size(obj.primal_vars{i}.sub_vars));
                for j=1:num_sub_vars
                    abs_idx = obj.primal_vars{i}.sub_vars{j}.idx - obj.primal_vars{i}.idx;
                    obj.primal_vars{i}.sub_vars{j}.val = ...
                        obj.primal_vars{i}.val(abs_idx+1:abs_idx+obj.primal_vars{i}.sub_vars{j}.dim);
                end
            end

            for i=1:obj.num_dual_vars
                idx = obj.dual_vars{i}.idx;
                obj.dual_vars{i}.val = result.y(idx+1:idx+ ...
                                                obj.dual_vars{i}.dim);
                
                num_sub_vars = prod(size(obj.dual_vars{i}.sub_vars));
                for j=1:num_sub_vars
                    abs_idx = obj.dual_vars{i}.sub_vars{j}.idx - obj.dual_vars{i}.idx;
                    obj.dual_vars{i}.sub_vars{j}.val = ...
                        obj.dual_vars{i}.val(abs_idx+1:abs_idx+obj.dual_vars{i}.sub_vars{j}.dim);
                end
            end
        end
        
        function obj = finalize(obj)
            zero_fn = zero();
            
            if isempty(obj.data.prox_g)
                obj.data.prox_g{end + 1} = zero_fn(0, obj.ncols);
            end

            if isempty(obj.data.prox_fstar)
                obj.data.prox_fstar{end + 1} = zero_fn(0, obj.nrows);
            end
        end
    end
end
