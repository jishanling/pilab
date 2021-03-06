% Ok, let's forget about sub-classing. All we need is a data field that
% contains the relevant inputs, a meta.samples.chunks field for
% surviving the input check in roidata2rdmvol_lindisc_batch, and nfeatures
% So if we use covariates as the data field we obtain the correct sample
% size, which is helpful for row-based indexing. But how ensure the right
% onsets and conind come with?
%
% So assumptions:
% data needs to contain the same number of rows as epivol
% meta.samples.chunks needs to be configured properly
% nfeatures needs to be nreg
%
% the ROIPRocessor only enters design.data into runrois_serial. So need to
% put all the parameters in here
%
% we can modify array2glm, vol2glm and roidata2rdmvol to relax these
% assumptions.
%   Specifically, replace GLMConstructor with a DesignConstructor. This
%   should work really nicely actually. Getting close now...
%
% If we forget the assumptions, the format that makes sense here is a struct
% array.
classdef DesignSpec < handle
    properties
        data
        nsamples
        nfeatures
        meta
    end

    methods
        function ds = DesignSpec(design,frameperiod,varargin)
            if ~any(nargin)
                design = emptystruct('onsets','conind','n','chunk',...
                    'covariates','convargs','frameperiod');
            end
            if iscell(design)
                % attempt to unpack, hopefully into struct array
                design = [design{:}];
                assert(isstruct(design),...
                    'input design must be struct or cell array of struct');
            end
            ds.data = design;
            % make sure chunks are coded appropriately
            for c = 1:numel(ds.data)
                if ~isfield(ds.data,'chunk') || isempty(ds.data(c).chunk)
                    ds.data(c).chunk = c;
                end
                if isscalar(ds.data(c).chunk)
                    ds.data(c).chunk = ones(ds.data(c).n,1) * c;
                end
                if ~isfield(ds.data,'convargs') || isempty(ds.data(c).convargs)
                    ds.data(c).convargs = varargin;
                end
                if ~isfield(ds.data,'frameperiod') || isempty(ds.data(c).frameperiod)
                    ds.data(c).frameperiod = frameperiod;
                end
            end
            ds.meta.samples.chunks = vertcat(ds.data.chunk);
            ds.nfeatures = numel(unique(design(1).conind));
            ds.nsamples = sum([design.n]);
        end

        function [X,errs] = designmatrix(self)
            for d = 1:numel(self.design)
                [X{d},errs{d}] = convolveonsets(self.design(d).onsets,...
                    self.design(d).conind,self.design(d).frameperiod,...
                    self.design(d).n,self.design(d).convargs{:});
            end
        end
    end
end
