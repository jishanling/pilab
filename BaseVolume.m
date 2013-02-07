classdef BaseVolume < handle
    % vol = Volume(data,varargin)
    % Base class for data storage.
    %
    % This class overloads Matlab's standard concatenation
    % functionality so it is possible to do e.g. volboth = [vola; volb] to
    % obtain a sensibly combined MriVolume instance.
    %
    % Similarly, direct indexing is overloaded so that e.g.
    % vol(1,:) returns a volume consisting only of the first data point.
    %
    % Optional named input arguments:
    % metasamples: struct of numeric or cell arrays with nsamples by 1 shape
    % metafeatures: struct numeric or cell arrays with 1 by nfeatures shape
    properties
        data % nsamples by nfeatures matrix
        nfeatures % number of in-mask voxels (columns in data)
        nsamples % number of sample points (rows in data)
        meta = struct('samples',[],'features',[]); % meta inputs go here
        desc = struct('samples',[],'features',[]); % summaries of meta
        standardstruct = struct('labels',{{}},'chunks',[],...
                'names',{{}},'order',[]);
    end

    methods
        function vol = BaseVolume(data,varargin)
            % empty return for sub-classing
            if nargin==0
                return
            end
            assert(ndims(data)==2,...
                'input data must be nsamples by nfeatures matrix');
            vol.data = data;
            [vol.nsamples,vol.nfeatures] = size(data);
            vol.initialisemeta(varargin{:});
            vol.checkmeta;
        end

        function self = initialisemeta(self,varargin)
        % handle the basic parsing of named meta arguments. Used in
        % initialisation method of sub-classes.
        % self = initialisemeta(self,varargin)
            standardvalues = structfun(@(x)x,self.standardstruct,...
                'uniformoutput',false);
            standardfields = fieldnames(self.standardstruct);
            getArgs(varargin,{'metasamples',self.standardstruct,...
                'metafeatures',self.standardstruct},'verbose=0',...
                'suppressUnknownArgMessage=1');
            % insure meta samples and features contain mandatory
            % fields from self.standardstruct
            self.meta.samples = catstruct(self.standardstruct,metasamples);
            self.meta.features = catstruct(self.standardstruct,...
                metafeatures);
        end

        function medianfilter(self,n)
        % medianfilter(n)
        % filter the data in place along the sample dimension (time) with
        % filter size n. Operates separately on each chunk.
            for c = 1:self.desc.samples.nunique.chunks
                chunkind = self.meta.samples.chunks == ...
                    self.desc.samples.unique.chunks(c);
                self.data(chunkind,:) = medianfilter(...
                    self.data(chunkind,:),n);
            end
        end

        function sgdetrend(self,k,f)
            % use a Savitzky-Golay filter to detrend the data across time.
            % Operates separately on each chunk
            for c = 1:self.desc.samples.nunique.chunks
                chunkind = self.meta.samples.chunks == ...
                    self.desc.samples.unique.chunks(c);
                self.data(chunkind,:) = self.data(chunkind,:) - ...
                    sgolayfilt(self.data(chunkind,:),k,f,[],1);
            end
        end

        function zscore(self)
            % Zscore the data across time, operating separately on each
            % chunk.
            for c = 1:self.desc.samples.nunique.chunks
                chunkind = self.meta.samples.chunks == ...
                    self.desc.samples.unique.chunks(c);
                self.data(chunkind,:) = zscore(self.data(chunkind,:),[],...
                    1);
            end
        end

        function checkmeta(self)
        % add desc data for each meta field, check that meta data is in
        % register.
        % checkmeta(self)
            for fn = fieldnames(self.standardstruct)'
                fnstr = fn{1};
                % get standard fields - unique, indices, nunique
                [self.desc.samples.unique.(fnstr),...
                    junk,self.desc.samples.inds.(fnstr)] = ...
                    unique(self.meta.samples.(fnstr));
                self.desc.samples.nunique.(fnstr) = length(...
                    self.desc.samples.unique.(fnstr));
                [self.desc.features.unique.(fnstr),...
                    junk,self.desc.features.inds.(fnstr)] = ...
                    unique(self.meta.features.(fnstr));
                self.desc.features.nunique.(fnstr) = length(...
                    self.desc.features.unique.(fnstr));
            end
            % check that the meta samples/features are in register with
            % the data matrix
            assert(all(structfun(@(x)isempty(x) || ...
                (length(x)==self.nsamples),self.meta.samples)),...
                'mismatch between nsamples and meta.samples length');
            assert(all(structfun(@(x)isempty(x) || ...
                (length(x)==self.nfeatures),self.meta.features)),...
                'mismatch between nfeatures and meta.features length');
            if isempty(self.meta.samples.order)
                self.meta.samples.order = (1:self.nsamples)';
            end
        end

        function [sampind,featind] = findbymeta(self,varargin)
        % [sampind,featind] = findbymeta(self,varargin)
        % return logical indices into samples and features according to
        % some meta data. Mainly used internally to support selectbymeta
        % and removebymeta.
            % get possible names
            validsamp = fieldnames(self.meta.samples);
            validfeat = fieldnames(self.meta.features);
            valid = union(validsamp,validfeat);
            getArgs(varargin,valid);
            % begin by assuming you want everything
            sampind = true(self.nsamples,1);
            featind = true(1,self.nfeatures);
            for v = valid'
                vstr = v{1};
                % skip if not passed as input
                if ieNotDefined(vstr)
                    continue
                end
                value = eval(vstr);
                % check that the field is in samples and is not empty
                insamp = isfield(self.meta.samples,vstr) && ...
                    ~isempty(self.meta.samples.(vstr));
                infeat = isfield(self.meta.features,vstr) && ...
                    ~isempty(self.meta.features.(vstr));
                % if you ask for meta data we can't find this is almost
                % certainly a problem
                assert(any([insamp infeat]),...
                        'meta data does not exist: %s',vstr)
                if insamp
                    inds = self.findbyvalue(...
                        self.meta.samples.(vstr),value);
                    sampind = sampind & inds;
                end
                if infeat
                    inds = self.findbyvalue(...
                        self.meta.features.(vstr),value);
                    featind = featind & inds;
                end
            end
        end

        function vol = selectbymeta(self,varargin)
        % convenience method for returning a volume with particular meta
        % data in samples/features dimension. Assumes that samples and
        % features are in register. You can pass any number of criteria and
        % any number of values for each criterion.
        % The resulting vol will be the intersection of all criteria.
        % vol = selectbymeta(self,varargin)
            [sampind,featind] = self.findbymeta(varargin{:});
            % convert to subsref format
            s = struct('type','()','subs',{{sampind,featind}});
            % here we OMIT the first argument which is effectively self,
            % since basesubsref is a dynamic method. I guess? This is very
            % puzzling.
            [dat,meta] = self.basesubsref(s);
            % finally, use the appropriate, potentially sub-classed copy
            % method.
            vol = self.copy(dat,meta);
        end

        function vol = removebymeta(self,varargin)
        % convenience method for returning a volume WITHOUT particular meta
        % data in samples/features dimension. Otherwise similar to
        % selectbymeta.
        % vol = removebymeta(self,varargin)
            [sampind,featind] = self.findbymeta(varargin{:});
            if ~all(sampind)
                sampind = ~sampind;
            end
            if ~all(featind)
                featind = ~featind;
            end
            % convert to subsref format
            s = struct('type','()','subs',{{sampind,featind}});
            % here we OMIT the first argument which is effectively self,
            % since basesubsref is a dynamic method. I guess? This is very
            % puzzling.
            [dat,meta] = self.basesubsref(s);
            % finally, use the appropriate, potentially sub-classed copy
            % method.
            vol = self.copy(dat,meta);
        end

        function vol = copy(self,dat,meta)
            vol = BaseVolume(dat,'metasamples',meta.samples,...
                'metafeatures',meta.features);
        end

        function varargout = subsref(a,s)
        % varargout = subsref(a,s)
            switch s(1).type
                case '()'
                    % basic parsing
                    [dat,meta] = basesubsref(a,s);
                    % make a new instance
                    varargout{1} = BaseVolume(dat,'metasamples',meta.samples,...
                        'metafeatures',meta.features);
                otherwise
                    % revert to builtin behaviour
                    try
                        varargout{1} = builtin('subsref',a,s);
                    catch
                        % maybe no output?
                        builtin('subsref',a,s);
                    end
            end
        end

        function [dat,meta] = basesubsref(a,s)
        % basic subsref behaviour. Should be called in subclass subsref.
        % It's a bit baffling, but Matlab will not tolerate having these
        % subsref methods in the Static,Private field below...
        % [dat,meta] = basesubsref(a,s)
            assert(length(s)==1,...
                'cannot subindex instance');
            % if no column index, assume you want all features
            if length(s.subs)==1
                s.subs{2} = 1:a.nfeatures;
            end
            % pull out data field 
            dat = builtin('subsref',a.data,s);
            % handle special cases
            datind = s.subs{1};
            if strcmp(datind,':')
                datind = 1:a.nsamples;
            end
            % update meta data
            meta.samples = a.indexstructfields(a.meta.samples,datind);
            % if we are also indexing in feature dimension
            if length(s.subs) > 1 
                % update meta features
                meta.features = a.indexstructfields(a.meta.features,...
                    s.subs{2});
            end
        end
        % for mysterious reasons operator overloading only works for
        % dynamic methods it seems
        function o = horzcat(varargin)
            error('concatenation in feature dimension is not supported')
        end

        function o = vertcat(varargin)
            % construct a volume where the mask is read from the first
            % entry and all instances are passed as is. Should concatenate
            % nicely
            % this is needed to insure that the correct sub-class is called
            cl = class(varargin{1});
            o = feval(cl,varargin);
        end

        function o = cat(dim,varargin)
            % Identical to horzcat - effectively this is a 1D class
            assert(dim==1,'concatenation is only supported in data dim')
            o = vertcat(varargin{:});
        end

    end

    methods(Static)
        function inds = findbyvalue(array,item)
            if ischar(item) || (iscell(item) && ischar(item{1}))
                assert(iscell(array) && isa(array{1},'char'),...
                    'array must be cell with char entries');
                if ~iscell(item)
                    item = {item};
                end
                inds = strcmp(item{1},array);
                % support OR behaviour for multiple inputs
                for x = 2:length(item)
                    inds = strcmp(item{x},array) | inds;
                end
            elseif isnumeric(item)
                assert(isnumeric(array),'array must be numeric');
                inds = item(1) == array;
                % support OR behaviour for multiple inputs
                for x = 2:length(item)
                    inds = (item(x) == array) | inds;
                end
            else
                error('unrecognised input class: %s',class(item));
            end
        end

        function out = indexstructfields(in,inds)
        % Return a struct where each field has been indexed with the same
        % inds. Used internally to insure that any custom meta data/features
        % stay in register when the data gets indexed.
        % out = indexstructfields(in,inds)
            sfields = fieldnames(in);
            % special treatment of empties since we can't index these
            empties = structfun(@isempty,in);
            % get data for the remaining
            validdata = structfun(@(x)x(inds),...
                rmfield(in,sfields(empties)),'uniformoutput',false);
            % return the empties (with correct type whatever that may be)
            emptydata = structfun(@(x)x,rmfield(in,sfields(~empties)),...
                'uniformoutput',false);
            % recombine for the final struct
            out = catstruct(validdata, emptydata);
        end

        function org = appendstructfields(org,new,dim)
        % Return a struct where the consistent fields between org and new
        % have been appended (rather than the last overwriting the first as
        % in catstruct). Recurses into sub-fields.
        % org = appendstructfields(org,new,dim)
            orgfields = fieldnames(org);
            newfields = fieldnames(new);
            % fields that need updating
            toupdate = intersect(orgfields,newfields)';
            % concatenate when needed
            for t = toupdate
                tstr = t{1};
                if isstruct(org.(tstr))
                    % recurse into sub-fields
                    org.(tstr) = appendstructfields(org.(tstr),...
                        new.(tstr),dim);
                else
                    org.(tstr) = cat(dim,org.(tstr),new.(tstr));
                end
            end
            % fields that need to be added
            trulynew = setdiff(newfields,orgfields)';
            for n = trulynew
                nstr = n{1};
                org.(tstr) = new.(tstr);
            end
        end

    end
end